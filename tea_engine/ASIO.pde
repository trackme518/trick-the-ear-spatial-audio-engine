/*
 Uses: https://github.com/mhroth/jasiohost
 Include JAsioHost.jar in your Java project.
 Make jasiohost.dll available to your project. This can be done in several ways:
 Move or copy the library to C:\WINDOWS\system32. This is the default search location for JNI libraries.
 Inform the JVM where the library is located. This can be done with, e.g. java -Djava.library.path=C:\WINDOWS\system32
 https://github.com/mhroth/jasiohost/blob/master/src/com/synthbot/jasiohost/ExampleHost.java
 
 JAsioHost is released under the Lesser Gnu Public License (LGPL). 
 Basically, the library stays open source, but you can use if for whatever you want, including closed source applications. 
 You must publicly credit the use of this library.
 
 */

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
