/*
AudioEngine is the main class that handles playback
 AudioEngine holds reference to AudioBackend class that encapsulate OS specific low level class to actually send audio to outputs
 On Windows I am using ASIO
 MacOS + Linux not implemnted yet
 */

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
  //ArrayList<Integer> subChannels = new ArrayList<>();

  BiquadFilter subLowpass;

  ChannelRecorder[] recorders;
  boolean recordingEnabled = false;
  int recordingChannels = 8;
  String recordingsPath = dataPath("recordings");
  String lastRecordingPath = recordingsPath;

  SharedHrtfContext sharedHRTF;

  SpatialAudio spatialEngine;

  AudioBackend backend; //depends on current OS, on Windows use ASIO
  String[] deviceNames; //string names of avaliable devices

  // ===================== CONSTRUCTOR =====================
  AudioEngine() {

    spatialEngine = new SpatialAudio();

    if (platform == WINDOWS) {
      println("Running on Windows");
      backend = new AsioBackend();
    } else if (platform == MACOS) {
      println("Running on macOS"); //does nothing
      backend = new CoreAudioBackend();
    } else if (platform == LINUX) {
      backend = new JackBackend();
      //TBD implement backend for Linux later
      println("Running on Linux"); //does nothing
    } else {
      println("Unknown OS"); //does nothing
    }


    this.getDeviceNames(); //let user choose device based on its name
    File folder = new File(dataPath(recordingsPath));
    if (!folder.exists()) {
      folder.mkdirs();
    }
  }

  //only when the device is opened we start the engine
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

    if (playlists==null) return; //safe gurad - we need this global variable reference to actual sound file buffers

    if (!playlists.playlist.isPlaying) {
      write(outputs);
      return;
    }

    // === TRACK PROCESSING ============================
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

      //--normal multichannel-------------------------
      for (int c = 0; c < channelCount; c++) {
        float gain = currTrack.getGain(c);
        if (currTrack.mute) gain = 0f;
        for (int i = 0; i < read; i++) {
          outputBuffers.get(c)[i] += block[i] * gain * this.volume;
        }
      }
    }

    // === Subwoofer low pass ==========================
    if (applyLowpass && !binaural && !spatialEngine.preset.subChannels.isEmpty()) {
      float[] sub = new float[bufferSize];
      for (int i = 0; i < bufferSize; i++) {
        float mixed = 0;
        for (float[] ch : outputBuffers) mixed += ch[i];
        mixed /= channelCount;
        sub[i] = subLowpass.process(mixed);
      }
      //for (int idx : spatialEngine.preset.subChannels) {
      for (int idx : spatialEngine.preset.subChannels) {
        if (idx < 0 || idx >= outputBuffers.size()) {
          //println("Invalid sub channel index: " + idx); //higher than avaliable channels out
          continue;
        }
        outputBuffers.set(idx, sub);
      }
    }
    //----end for subwoofers-----------------------------

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
