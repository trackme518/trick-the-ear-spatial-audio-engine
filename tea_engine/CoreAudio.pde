/*
Uses: https://github.com/mhroth/JCoreAudio/tree/master
Include JCoreAudio.jar in your Java project.
Make libJCoreAudio.jnilib available to your project. This can be done in several ways:
Move or copy the library to /Library/Java/Extensions. This is the default search location for JNI libraries.
Inform the JVM where the library is located. This can be done with, e.g. java -Djava.library.path=/Library/Java/Extensions

JCoreAudio is licensed under a modified LGPL with a non-commercial clause, in the spirit of the Creative Commons Attribution-NonCommercial (CC BY-NC) license. 
Anyone wishing to use JCoreAudio commercially should contact me directly.

*/

import ch.section6.jcoreaudio.*;
import java.nio.FloatBuffer;
import java.util.*;

class CoreAudioBackend implements AudioBackend {

  private AudioCallback callback;

  private int bufferSize;
  private float sampleRate;
  private int channels;
  private boolean active = false;

  private float[][] backendBuffers;

  private AudioDevice outputDevice;
  private Set<AudioLet> outputLets;

  private long samplePosition = 0;

  // =====================================================
  @Override
    public void open(String deviceName) {

    List<AudioDevice> devices = JCoreAudio.getAudioDeviceList();

    outputDevice = devices.stream()
      .filter(d -> d.getName().equals(deviceName))
      .findFirst()
      .orElseThrow(() ->
      new RuntimeException("CoreAudio device not found: " + deviceName));

    outputLets = outputDevice.getOutputSet();

    bufferSize = outputDevice.getCurrentBufferSize();
    sampleRate = outputDevice.getCurrentSampleRate();

    channels = outputLets.stream()
      .mapToInt(l -> l.numChannels)
      .sum();

    backendBuffers = new float[channels][bufferSize];

    JCoreAudio.getInstance().initialize(
      null,
      outputLets,
      bufferSize,
      sampleRate
      );

    JCoreAudio.getInstance().setListener(listener);
  }

  // =====================================================
  private final CoreAudioListener listener = new CoreAudioListener() {

    @Override
      public void onCoreAudioInput(double ts, Set<AudioLet> inputLets) {
      // not used
    }

    @Override
      public void onCoreAudioOutput(double ts, Set<AudioLet> lets) {

      if (callback == null) return;

      callback.process(
        backendBuffers,
        bufferSize,
        System.nanoTime(),
        samplePosition
        );

      int ch = 0;

      for (AudioLet let : lets) {
        for (int c = 0; c < let.numChannels; c++) {
          FloatBuffer buffer = let.getChannelFloatBuffer(c);
          buffer.rewind();
          buffer.put(backendBuffers[ch + c]);
        }
        ch += let.numChannels;
      }

      //samplePosition += bufferSize;
      samplePosition = (long)(ts * sampleRate); //using CoreAudio timestamp
    }
  };

  // =====================================================
  @Override public void start() {
    JCoreAudio.getInstance().play();
    active = true; //actually might be false / not started if there is an error? 
  }

  @Override public void close() {
    JCoreAudio.jcoreaudio.returnToState(CoreAudioState.UNINITIALIZED);
    active = false; 
  }

  // =====================================================
  @Override public void setCallback(AudioCallback cb) {
    this.callback = cb;
  }

  @Override public boolean isActive() {
    return active;
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
    public String[] getDeviceNames() {
    return JCoreAudio.getAudioDeviceList()
      .stream()
      .map(AudioDevice::getName)
      .toArray(String[]::new);
  }

  @Override public void resetRequest() {
  }
  @Override public void openControlPanel() {
  }
}
