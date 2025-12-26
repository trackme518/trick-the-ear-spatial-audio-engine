// ASIO interface for Windows audio realtime multichannel playback 

import java.util.HashMap; // import the HashMap class

class AsioHost implements AsioDriverListener {
  //BinauralAudioProcessor hrtf; // i need one instance per Track due to overlap-add buffer for hrirs
  boolean binaural = false; //binaural output enabled instead of multichannel speaker output its either OR

  //private static final long serialVersionUID = 1L;
  AsioDriver asioDriver;
  // create a Set of AsioChannels, defining which input and output channels will be used
  //ArrayList<AsioChannel>activeChannelsList;
  Set<AsioChannel>activeChannels = new HashSet<AsioChannel>();//in java HashSet is missing get() method....
  HashMap<Integer, AsioChannel> activeChannelsMap = new HashMap<Integer, AsioChannel>();//so lets convert it into HashMap to be able to effectively retrieve elements without iterating
  int outputChannelsCount = 0; //just for convenience to use with gui - essentially activeChannels.size();
  //------------------------
  BiquadFilter subLowpass; //filter out low frequencies from output buffer, see lowpasss tab
  boolean applyLowpass = true;
  ArrayList<Integer>subChannels = new ArrayList<Integer>(); //let user set which channels should be used for subwoofer output
  //------------------------
  private long sampleIndex;
  private int bufferSize;
  private double sampleRate;
  //----------------------------------------------
  //for testing which channel is which - util functions
  private int testChannelIndex = 0;//when positive it will send noise sound into given channel (for debugging)
  public boolean isTestingMode = false;
  //---------------------------------------------------
  private float volume = 1.0;
  ArrayList<float[]>outputBuffers = new ArrayList<float[]>();
  //---------------------------------------
  ChannelRecorder[] recorders; //enable per channel recording - see Recorder tab; ChannelRecorder class
  boolean recordingEnabled = false;
  String recordingsPath = dataPath("recordings");
  int recordingChannels = 8;//max channels to record
  String lastRecordingPath = recordingsPath;
  //---------------------------------
  AsioDriverListener host;

  //float[] sampleBuffer; //from processing sound library - read audio sample into float -1/+1 range buffer
  //int sampleBufferRate; //sound library - rate of the buffer

  String[] asioDeviceNames; //string names of avaliable ASIO devices

  boolean outpputActive = false;

  AsioHost() {
    this.host = this;
    this.asioDeviceNames = this.getAsioDeviceNames();
    //this.testNoise = getLoopedNoise(512);
    //sampleBuffer = new float[512];//zereos of integral types are guaranteed - initialized
    //this.testNoiseBuffer = getLoopedNoise(1024);
    File folder = new File(dataPath(recordingsPath));
    if (!folder.exists()) {
      folder.mkdirs();
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

  String[] getAsioDeviceNames() {
    List<String> driverNameList = AsioDriver.getDriverNames();
    return driverNameList.toArray(new String[0]);
  }
  //------------------------------------------------------------------------------
  //Record wav file per channel output
  void initRecorders() {
    this.stopRecording();

    this.recorders = new ChannelRecorder[asioDriver.getNumChannelsOutput()];
    for (int i = 0; i < recorders.length; i++) {
      recorders[i] = new ChannelRecorder(i, (int)this.sampleRate, this.bufferSize);
    }
    println("Recording set for "+this.recordingChannels+" channels");
  }
  //-------------------------------------
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
  //-----------------------------------------------------------------------------------
  void activate(String _drivername) {
    this.close(); //stop if previously opened
    //this.activeChannels =  new ArrayList<AsioChannel>();
    this.activeChannels = new HashSet<AsioChannel>();

    this.activeChannelsMap = new HashMap<Integer, AsioChannel>();

    if (asioDriver == null) {
      try {
        this.asioDriver = AsioDriver.getDriver(_drivername);
      }
      catch(Exception e) {
        println(e);
        return;
      }
      this.asioDriver.addAsioDriverListener(this.host); //this will attach default callback to itself - bufferSwitch fce
      // configure the ASIO driver to use the given channels

      this.sampleIndex = 0;
      this.bufferSize = asioDriver.getBufferPreferredSize();
      this.sampleRate = asioDriver.getSampleRate();

      outputBuffers.clear();
      for (int i = 0; i < asioDriver.getNumChannelsOutput(); i++) {
        //create unique output buffer for each channel
        outputBuffers.add( new float[this.bufferSize] );
        //inputs
        //AsioChannel asioChannel = asioDriver.getChannelInput(i);
        //outputs
        AsioChannel asioChannel = asioDriver.getChannelOutput(i);
        this.activeChannels.add(asioChannel);//needed because "this.asioDriver.createBuffers" expects HashSet for some reason...
        this.activeChannelsMap.put(i, asioChannel);//just create HashMap that is nicer to work with, with the same instance
      }

      //this.output = new float[bufferSize];
      this.asioDriver.createBuffers(activeChannels);
      this.asioDriver.start();
      this.outputChannelsCount = activeChannels.size();
      println("started asio host, rate: "+this.sampleRate+"Hz buffer  size: "+bufferSize + " output channels: "+asioDriver.getNumChannelsOutput() );
      this.outpputActive = true; //set internal flag
      //started asio host, rate: 48000.0Hz buffer  size: 512 output channels: 8

      //init lowpass class
      subLowpass = new BiquadFilter(120.0, (float)this.sampleRate); // 120Hz cutoff

      this.initRecorders();

      //setup hrtf based on buffersize--------------------
      sharedHRTF = new SharedHrtfContext(this.bufferSize); //global singleton

      for (int p=0; p<playlists.playlists.size(); p++) {
        Playlist playlist = playlists.playlists.get(p);
        for (int i=0; i<playlist.samples.size(); i++) {
          Track currTrack = playlist.getTrack(i);
          currTrack.virtualSource.initHrtf(sharedHRTF);//set shared instance
        }
      }

      //-------------------------------------------------------------------
    }
  }

  void openControlPanel() {
    if (asioDriver != null &&
      asioDriver.getCurrentState().ordinal() >= AsioDriverState.INITIALIZED.ordinal()) {
      asioDriver.openControlPanel();
    }
  }

  void resetPlayhead() {
    this.sampleIndex = 0;
  }

  void close() {
    if (asioDriver != null) {
      this.outputChannelsCount = 0;
      this.asioDriver.shutdownAndUnloadDriver();
      this.activeChannels.clear();
      this.asioDriver = null;
      println("host stopped");
      this.outpputActive = false; //set internal flag
    }
  }


  public void resyncRequest() {
    System.out.println("resyncRequest() callback received.");
  }

  public void resetRequest() {
    this.outputChannelsCount = 0;
    new Thread() {
      @Override public void run() {
        System.out.println("resetRequest() callback received. Returning driver to INITIALIZED state.");
        asioDriver.returnToState(AsioDriverState.INITIALIZED);
      }
    }
    .start();
  }

  public void bufferSwitch(long systemTime, long samplePosition, Set<AsioChannel> channels) {
    // --- Clear output buffers (silence) ---
    for (int i = 0; i < this.outputBuffers.size(); i++) {
      Arrays.fill(this.outputBuffers.get(i), 0f);
    }

    // --- Testing mode: perlin noise output ---
    if (this.isTestingMode) {
      int channelIndex = 0;
      for (AsioChannel channelInfo : channels) {
        if (channelIndex == this.testChannelIndex) {
          for (int b = 0; b < this.bufferSize; b++) {
            outputBuffers.get(channelIndex)[b] = random(-1, 1) * this.volume;
          }
        }
        channelInfo.write(outputBuffers.get(channelIndex));
        channelIndex++;
      }
      return;
    }

    // --- Playlist not playing: write silence ---
    if (!playlists.playlist.isPlaying) {
      int channelIndex = 0;
      for (AsioChannel channelInfo : channels) {
        channelInfo.write(outputBuffers.get(channelIndex));
        channelIndex++;
      }
      return;
    }

    // --- Process each track ---
    for (int i = 0; i < playlists.playlist.samples.size(); i++) {
      Track currTrack = playlists.playlist.getTrack(i);

      if (!currTrack.isPlaying()) continue;
      
      if(currTrack.mute) continue;

      // --- Compute global track position and remaining frames ---
      int trackPos = (int) (this.sampleIndex - currTrack.sampleIndexOffset);
      int framesLeft = (int) Math.max(0, currTrack.totalFrames - trackPos);

      // Skip track if finished and not looped
      if (framesLeft <= 0 && !currTrack.looped) continue;

      int framesToRead = Math.min(this.bufferSize, framesLeft);

      // --- HRTF binaural output ---
      if (this.binaural && this.activeChannels.size() > 1 && currTrack.virtualSource.hrtf != null) {
        float[] block = new float[framesToRead];
        try {
          int read = currTrack.read(block, framesToRead);
          if (read > 0) {
            float[][] binauralOut = currTrack.virtualSource.hrtf.process(block);
            for (int b = 0; b < read; b++) {
              outputBuffers.get(0)[b] += binauralOut[0][b] * this.volume;
              outputBuffers.get(1)[b] += binauralOut[1][b] * this.volume;
            }
          }
        }
        catch (IOException e) {
          e.printStackTrace();
        }
        continue; // skip normal channel output
      }

      // --- Normal channel output (non-HRTF) ---
      for (int c = 0; c < this.activeChannels.size(); c++) {
        float[] outBuffer = outputBuffers.get(c);
        float[] block = new float[framesToRead];
        try {
          int read = currTrack.read(block, framesToRead);
          //float gain = currTrack.gains.getOrDefault(c, 0.0f);
          float gain = currTrack.getGain(c);
          if (currTrack.mute) gain = 0f;
          for (int b = 0; b < read; b++) {
            outBuffer[b] += block[b] * gain * this.volume;
          }
        }
        catch (IOException e) {
          e.printStackTrace();
        }
      }
    }

    // --- Mix low frequencies into subwoofer channel ---
    if (this.applyLowpass && !this.binaural) {
      float[] subBuffer = new float[this.bufferSize];
      for (int i = 0; i < bufferSize; i++) {
        float mixed = 0;
        for (int c = 0; c < outputBuffers.size(); c++) {
          mixed += outputBuffers.get(c)[i];
        }
        mixed /= outputBuffers.size();
        subBuffer[i] = subLowpass.process(mixed);
      }
      for (int i = 0; i < subChannels.size(); i++) {
        outputBuffers.set(subChannels.get(i), subBuffer);
      }
    }

    // --- Send outputBuffers to ASIO channels and optionally record ---
    int channelIndex = 0;
    for (AsioChannel channelInfo : channels) {
      channelInfo.write(outputBuffers.get(channelIndex));
      if (recordingEnabled && channelIndex < this.recordingChannels) {
        recorders[channelIndex].addSamples(outputBuffers.get(channelIndex));
      }
      channelIndex++;
    }

    // --- Increment global sample index ---
    this.sampleIndex += this.bufferSize;
  }



  public void bufferSizeChanged(int bufferSize) {
    System.out.println("bufferSizeChanged() callback received.");
  }

  public void sampleRateDidChange(double sampleRate) {
    System.out.println("sampleRateDidChange() callback received.");
  }

  public void latenciesChanged(int inputLatency, int outputLatency) {
    System.out.println("latenciesChanged() callback received.");
  }

  float[] resample(float[] data, int dataRate, int outputRate) {
    if ( dataRate==22050 && outputRate==44100) { //half
      println("half input rate - double the output buffer");
      float[] dataout = new float[ data.length*2 ];
      for (int i=0; i<dataout.length; i++) {
        if ((i+1)/2<data.length) {
          dataout[i] = data[i/2];
          dataout[i+1] = data[i/2];
        }
      }
      return dataout;
    } else if ( dataRate==22050 && outputRate==48000 ) {
      println("DEBUG");
      float[] dataout = new float[ data.length*2 ];
      for (int i=0; i<dataout.length; i++) {
        if ((i+1)/2<data.length) {
          dataout[i] = data[i/2];
          dataout[i+1] = data[i/2];
        }
      }
      return dataout;
    } else if ( dataRate==44100 && outputRate==48000 ) {
      //implement
    } else if ( dataRate==48000 && outputRate==44100 ) {
      //implement
    }
    return data;
    //}
  }
}
