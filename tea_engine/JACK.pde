/*
Uses: https://github.com/jaudiolibs/jnajack
 
 ABSOLUTELEY UNTESTED!!! Skeleton
 */

import org.jaudiolibs.jnajack.*;
import java.util.*;
import java.nio.FloatBuffer;


import java.util.EnumSet;
import java.util.List;

import org.jaudiolibs.jnajack.lowlevel.JackLibrary;
import com.sun.jna.Pointer;

//================================================================================
// JACK interface for Linux realtime multichannel playback
class JackBackend implements AudioBackend, JackProcessCallback {

  private JackClient client;
  private AudioCallback callback;

  private int bufferSize;
  private int channels;
  private double sampleRate;
  private boolean outputActive = false;

  private float[][] backendBuffers;

  private final List<JackPort> outputPorts = new ArrayList<>();

  private long samplePosition = 0;

  private static final String JACK_AUDIO_TYPE ="32 bit float mono audio";

  // =====================================================
  @Override
    public void open(String clientName) {

    try {
      client = Jack.getInstance().openClient(
        clientName,
        EnumSet.of(JackOptions.JackNoStartServer),
        EnumSet.noneOf(JackStatus.class)
        );

      if (client == null) {
        throw new RuntimeException("JACK client is null");
      }

      bufferSize = client.getBufferSize();
      sampleRate = client.getSampleRate();

      // stereo default (adjust if needed)
      channels = 2;

      backendBuffers = new float[channels][bufferSize];
      outputPorts.clear();

      for (int i = 0; i < channels; i++) {
        JackPort port = client.registerPort(
          "out_" + (i + 1),
          JackPortType.AUDIO,
          EnumSet.of(JackPortFlags.JackPortIsOutput)
          );
        outputPorts.add(port);
      }

      client.setProcessCallback(this);

      connectToSystemOutputs();
    }
    catch (JackException e) {
      throw new RuntimeException("Failed to connect to JACK server", e);
    }
  }

  // =====================================================

  private void connectToSystemOutputs() {

    try {
      String[] systemPorts = Jack.getInstance().getPorts(
        client,
        "system:.*",
        JackPortType.AUDIO,
        EnumSet.of(JackPortFlags.JackPortIsInput)
        );

      if (systemPorts == null || systemPorts.length == 0) {
        System.err.println("No JACK system playback ports found");
        return;
      }

      for (int i = 0; i < Math.min(outputPorts.size(), systemPorts.length); i++) {
        Jack.getInstance().connect(
          client,
          outputPorts.get(i).getName(),
          systemPorts[i]
          );
      }
    }
    catch (JackException e) {
      throw new RuntimeException("Failed to connect JACK outputs", e);
    }
  }


  // =====================================================
  @Override
    public boolean process(JackClient client, int nframes) {

    if (!outputActive || callback == null) {
      // Silence output
      for (JackPort port : outputPorts) {
        FloatBuffer fb = port.getFloatBuffer();
        fb.clear();
        for (int i = 0; i < nframes; i++) {
          fb.put(0f);
        }
      }
      return true;
    }

    // Ensure buffer size consistency
    if (nframes != bufferSize) {
      bufferSize = nframes;
      backendBuffers = new float[channels][bufferSize];
    }

    // Call engine callback
    callback.process(
      backendBuffers,
      bufferSize,
      System.nanoTime(),
      samplePosition
      );

    // Write to JACK ports
    for (int c = 0; c < channels; c++) {
      FloatBuffer fb = outputPorts.get(c).getFloatBuffer();
      fb.rewind();
      fb.put(backendBuffers[c]);
    }

    samplePosition += bufferSize;
    return true;
  }

  // =====================================================
  @Override
    public void start() {
    try {
      client.activate();
    }
    catch (JackException e) {
      throw new RuntimeException("Failed to connect to JACK server", e);
    }
    outputActive = true;
  }

  @Override
    public void close() {
    if (client != null) {
      client.deactivate();
      client.close();
      client = null;
    }
    outputActive = false;
  }

  // =====================================================
  @Override
    public void setCallback(AudioCallback cb) {
    this.callback = cb;
  }

  @Override
    public boolean isActive() {
    return outputActive;
  }

  @Override
    public int getBufferSize() {
    return bufferSize;
  }

  @Override
    public double getSampleRate() {
    return sampleRate;
  }

  @Override
    public int getOutputChannelCount() {
    return channels;
  }

  // =====================================================
  @Override
    public String[] getDeviceNames() {
    // JACK has one logical device (the server)
    return new String[] { "JACK Audio Server" };
  }

  @Override
    public void resetRequest() {
    // JACK handles this internally
  }

  @Override
    public void openControlPanel() {
    // Typically qjackctl (external)
  }
}
