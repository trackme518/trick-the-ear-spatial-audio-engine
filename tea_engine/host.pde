import java.util.HashMap; // import the HashMap class

interface AudioBackend {
  void open(String deviceName);
  void close();
  void start();
  void resetRequest();//potentially ASIO only
  void openControlPanel();//potentially ASIO only

  int getBufferSize();
  double getSampleRate();
  int getOutputChannelCount();
  String[] getDeviceNames();
  boolean isActive();


  void setCallback(AudioCallback callback);
}

@FunctionalInterface
  interface AudioCallback {
  void process(
    float[][] outputs,
    int bufferSize,
    long systemTime,
    long samplePosition
    );
}

class AudioEngine {

  // ===================== state =====================
  boolean binaural = false;
  boolean applyLowpass = true;
  boolean isTestingMode = false;

  int testChannelIndex = 0;
  float volume = 1.0f;

  long sampleIndex = 0;

  int bufferSize;
  int channelCount;
  double sampleRate;

  ArrayList<float[]> outputBuffers = new ArrayList<>();
  ArrayList<Integer> subChannels = new ArrayList<>();

  BiquadFilter subLowpass;

  ChannelRecorder[] recorders;
  boolean recordingEnabled = false;
  int recordingChannels = 8;
  String recordingsPath = dataPath("recordings");
  String lastRecordingPath = recordingsPath;

  SharedHrtfContext sharedHRTF;

  AudioBackend backend; //depends on current OS, on Windows use ASIO
  String[] deviceNames; //string names of avaliable devices



  // ===================== CONSTRUCTOR =====================
  AudioEngine() {
    if (platform == WINDOWS) {
      println("Running on Windows");
      backend = new AsioBackend();
    } else if (platform == MACOSX) {
      //TBD implement backend for MacOS later
      println("Running on macOS");
    } else if (platform == LINUX) {
      //TBD implement backend for Linux later
      println("Running on Linux");
    } else {
      println("Unknown OS");
    }


    this.getDeviceNames(); //let user choose device based on its name
    File folder = new File(dataPath(recordingsPath));
    if (!folder.exists()) {
      folder.mkdirs();
    }
  }

  void open(String deviceName) {
    backend.close();
    backend.setCallback(null);// Remove callback
    backend.open(deviceName);
    configureFromBackend(backend);
    backend.setCallback(this::process);
    backend.start();
  }

  String[] getDeviceNames() {
    this.deviceNames = this.backend.getDeviceNames();
    return this.deviceNames;
  }

  // ===================== CONFIG =====================
  void configureFromBackend(AudioBackend backend) {

    this.bufferSize   = backend.getBufferSize();
    this.sampleRate   = backend.getSampleRate();
    this.channelCount = backend.getOutputChannelCount();

    outputBuffers.clear();
    for (int c = 0; c < channelCount; c++) {
      outputBuffers.add(new float[bufferSize]);
    }

    subLowpass = new BiquadFilter(120.0, (float) sampleRate);

    // init HRTF AFTER bufferSize known
    sharedHRTF = new SharedHrtfContext(bufferSize, this::onHrtfReady);

    for (Playlist p : playlists.playlists) {
      for (Track t : p.samples) {
        t.virtualSource.initHrtf(sharedHRTF);
      }
    }

    initRecorders();
  }

  void onHrtfReady(SharedHrtfContext ctx) {
    for (Playlist p : playlists.playlists) {
      for (Track t : p.samples) {
        t.virtualSource.initHrtf(ctx);
      }
    }
  }

  void setVolume(float val) {
    this.volume = val;
  }

  void setTestingChannel(int _whichChannel) {
    this.testChannelIndex = _whichChannel;
  }

  void setTestSound(boolean _val) {
    this.isTestingMode = _val;
  }

  void resetPlayhead() {
    this.sampleIndex = 0;
  }

  // ===================== RECORDING =====================
  void initRecorders() {
    recorders = new ChannelRecorder[channelCount];
    for (int i = 0; i < channelCount; i++) {
      recorders[i] = new ChannelRecorder(i, (int) sampleRate, bufferSize);
    }
  }

  void startRecording() {
    if (this.recorders==null) {
      println("Please open the ASIO device before recording");
      return;
    }
    String timestamp = month()+"_"+day()+"_"+hour()+"_"+minute()+"_"+second();
    this.lastRecordingPath = this.recordingsPath +File.separator+timestamp;
    File folder = new File(this.lastRecordingPath);
    if (!folder.exists()) {
      folder.mkdirs();
    }

    try {
      for (int i = 0; i < recorders.length; i++) {
        if (i<this.recordingChannels) { //limit to user set max
          recorders[i].start(this.lastRecordingPath+File.separator+"rec_" + i + ".wav");
        }
      }
      recordingEnabled = true;
    }
    catch (Exception e) {
      println("failed to start recording");
      e.printStackTrace();
    }
  }
  //-----------------------------------
  void stopRecording() {
    recordingEnabled = false;
    if (recorders!=null) {
      for (ChannelRecorder r : recorders) {
        r.stop();
      }
    }
  }

  // ===================== AUDIO CALLBACK =====================
  void process(float[][] outputs, int bufferSize, long systemTime, long samplePosition) {

    // clear
    for (float[] buf : outputBuffers) {
      Arrays.fill(buf, 0f);
    }

    // testing mode
    if (isTestingMode) {
      for (int i = 0; i < bufferSize; i++) {
        outputBuffers.get(testChannelIndex)[i] =
          random(-1, 1) * volume;
      }
      write(outputs);
      return;
    }

    if (!playlists.playlist.isPlaying) {
      write(outputs);
      return;
    }

    // === TRACK PROCESSING ===
    for (Track currTrack : playlists.playlist.samples) {

      if (!currTrack.isPlaying() || currTrack.mute) continue;

      long trackPos   = sampleIndex - currTrack.sampleIndexOffset;
      long framesLeft = Math.max(0L, currTrack.totalFrames - trackPos);

      if (framesLeft <= 0 && !currTrack.looped) continue;

      int framesToRead = (int) Math.min(bufferSize, framesLeft);
      if (framesToRead <= 0) continue;

      float[] block = new float[framesToRead];
      int read;

      try {
        read = currTrack.read(block, framesToRead);
      }
      catch (IOException e) {
        e.printStackTrace();
        continue;
      }
      if (read <= 0) continue;

      // HRTF
      if (binaural && channelCount > 1 && currTrack.virtualSource.hrtf != null) {

        float[][] bin = currTrack.virtualSource.hrtf.process(block);
        for (int i = 0; i < read; i++) {
          outputBuffers.get(0)[i] += bin[0][i] * volume;
          outputBuffers.get(1)[i] += bin[1][i] * volume;
        }

        continue;
      }

      // normal multichannel
      for (int c = 0; c < channelCount; c++) {
        float gain = currTrack.getGain(c);
        if (currTrack.mute) gain = 0f;
        for (int i = 0; i < read; i++) {
          outputBuffers.get(c)[i] += block[i] * gain * this.volume;
        }
      }
    }

    // subwoofer
    if (applyLowpass && !binaural && !subChannels.isEmpty()) {
      float[] sub = new float[bufferSize];
      for (int i = 0; i < bufferSize; i++) {
        float mixed = 0;
        for (float[] ch : outputBuffers) mixed += ch[i];
        mixed /= channelCount;
        sub[i] = subLowpass.process(mixed);
      }
      for (int idx : subChannels) {
        outputBuffers.set(idx, sub);
      }
    }

    write(outputs);
    this.sampleIndex += this.bufferSize; //Increment global sample index
  }

  private void write(float[][] outputs) {
    for (int c = 0; c < channelCount; c++) {
      System.arraycopy(outputBuffers.get(c), 0, outputs[c], 0, bufferSize);
      if (recordingEnabled && c < this.recordingChannels) {//this.recordingChannels should be set to max speaker count or 2 in case of binaural...perhaps? or merge? TBD
        recorders[c].addSamples(outputBuffers.get(c));
      }
    }
  }
}



//================================================================================
// ASIO interface for Windows audio realtime multichannel playback
class AsioBackend implements AudioBackend, AsioDriverListener {

  AsioDriver asio;
  AudioCallback callback;

  int bufferSize;
  int channels;
  double sampleRate;
  boolean outputActive = false;

  float[][] backendBuffers;
  Set<AsioChannel> activeChannels = new HashSet<>();

  @Override
    public void open(String driverName) {
    asio = AsioDriver.getDriver(driverName);
    asio.addAsioDriverListener(this);//this will attach default callback to itself - bufferSwitch fce

    bufferSize = asio.getBufferPreferredSize();
    sampleRate = asio.getSampleRate();
    channels   = asio.getNumChannelsOutput();

    backendBuffers = new float[channels][bufferSize];

    activeChannels.clear();
    for (int i = 0; i < channels; i++) {
      activeChannels.add(asio.getChannelOutput(i));
    }

    asio.createBuffers(activeChannels);
  }

  @Override public boolean isActive() {
    return this.outputActive;
  }

  @Override public void start() {
    asio.start();
    this.outputActive = true; //set internal flag
  }

  @Override public void close() {
    if (asio!=null) {
      asio.shutdownAndUnloadDriver();
      this.asio = null;
      println("backend stopped");
    }
  }

  @Override public int getBufferSize() {
    return bufferSize;
  }
  @Override public double getSampleRate() {
    return sampleRate;
  }
  @Override public int getOutputChannelCount() {
    return channels;
  }

  @Override
    public void setCallback(AudioCallback cb) {
    this.callback = cb;
  }

  @Override
    public void bufferSwitch(long systemTime, long samplePosition, Set<AsioChannel> chans) {
    if (callback == null) return;

    callback.process(backendBuffers, bufferSize, systemTime, samplePosition);

    int i = 0;
    for (AsioChannel ch : chans) {
      ch.write(backendBuffers[i++]);
    }
  }

  @Override public  String[] getDeviceNames() {
    List<String> driverNameList = AsioDriver.getDriverNames();
    return driverNameList.toArray(new String[0]);
  }

  @Override public void sampleRateDidChange(double sr) {
    sampleRate = sr;
    println("sampleRateDidChange() callback received."); //this WILL break AudioEngine - should call for reinit upper class
  }
  
  @Override public void bufferSizeChanged(int bs) {
    bufferSize = bs;
    backendBuffers = new float[channels][bufferSize]; //this WILL break AudioEngine - should call for reinit upper class
    println("bufferSizeChanged() callback received.");
  }
  
  @Override public void latenciesChanged(int i, int o) {
    println("latenciesChanged() callback received.");
  }


  @Override public void resetRequest() {
    new Thread() {
      @Override public void run() {
        System.out.println("resetRequest() callback received. Returning driver to INITIALIZED state.");
        asio.returnToState(AsioDriverState.INITIALIZED);
      }
    }
    .start();
  }

  @Override public void resyncRequest() {
  }

  @Override public void openControlPanel() {
    if (asio != null &&
      asio.getCurrentState().ordinal() >= AsioDriverState.INITIALIZED.ordinal()) {
      asio.openControlPanel();
    }
  }
}
