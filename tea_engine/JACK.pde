/*
Uses: https://github.com/jaudiolibs/jnajack
 
 ABSOLUTELEY UNTESTED!!! Skeleton
 
 before running the app:
 jackd
 # or
 qjackctl → Start
 
 pipewire:
 sudo apt install pipewire-jack
 
 When you have pipewire installed (PopOS for example and modern Linux distros)
 verify you have pipewire installed and running:
 systemctl --user status pipewire
 
 install JACK compatible API with:
 sudo apt update
 sudo apt install pipewire-jack jackd2
 
 no need to set realtime privilieges (you can select no)
 Now log out and log in to resatrt audio services
 verify installation with command:
 pw-jack jack_lsp
 
 this is already included in modified launcher inside the release - see original for comparison.
 
 to run processing IDE though JACK using pipewire without exporting app:
 pw-jack processing
 (This makes every sketch you run JACK-enabled.)
 or:
 pw-jack ~/processing-4/processing
 
 when installed with flatpack
 first check the ID:
 flatpak list | grep Processing
 now run it with the ID via flatpack:
 pw-jack flatpak run org.processing.processingide
 
 
 pw-jack flatpak run org.processing.processingide --sketch=/full/path/to/your/sketch
 pw-jack flatpak run org.processing.processingide --sketch=/teaengine
 
 
 flatpack mabye does not accept input parameters :-( maybe i need to switch to native for this TBD
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

    String jackName = "myapp_" + System.nanoTime();

    try {
      client = Jack.getInstance().openClient(
        jackName,
        EnumSet.of(JackOptions.JackNoStartServer),
        EnumSet.noneOf(JackStatus.class)
        );

      if (client == null) {
        throw new RuntimeException("JACK client is null");
      }

      bufferSize = client.getBufferSize();
      sampleRate = client.getSampleRate();

      channels = 2; // fixed for now

      backendBuffers = null;   // IMPORTANT: allocate later
      outputPorts.clear();
      samplePosition = 0;
      outputActive = false;

      for (int i = 0; i < channels; i++) {
        JackPort port = client.registerPort(
          "out_" + (i + 1),
          JackPortType.AUDIO,
          EnumSet.of(JackPortFlags.JackPortIsOutput)
          );
        outputPorts.add(port);
      }

      // Safe even if callback is null
      client.setProcessCallback(this);
    }
    catch (JackException e) {
      throw new RuntimeException("Failed to connect to JACK server", e);
    }
  }


  // =====================================================

  private void connectToSystemOutputs() {
    try {
      String[] ports = Jack.getInstance().getPorts(
        client,
        null, // match all names
        JackPortType.AUDIO,
        EnumSet.of(JackPortFlags.JackPortIsInput)
        );

      println("==== JACK INPUT AUDIO PORTS ====");

      if (ports == null || ports.length == 0) {
        println("(none)");
        return;
      }

      for (String p : ports) {
        println(p);
      }

      println("==== END JACK INPUT AUDIO PORTS ====");

      // Filter for likely playback ports
      List<String> playbackPorts = new ArrayList<>();
      for (String p : ports) {
        String lp = p.toLowerCase();
        if (lp.contains("playback") || lp.contains("output")) {
          playbackPorts.add(p);
        }
      }

      if (playbackPorts.isEmpty()) {
        println("No matching playback ports");
        return;
      }

      println("==== SELECTED PLAYBACK PORTS ====");
      for (String p : playbackPorts) {
        System.err.println(p);
      }
      println("==== END SELECTED PLAYBACK PORTS ====");

      for (int i = 0; i < Math.min(outputPorts.size(), playbackPorts.size()); i++) {
        Jack.getInstance().connect(
          client,
          outputPorts.get(i).getName(),
          playbackPorts.get(i)
          );
      }

      println("Connected JACK outputs to playback ports");
    }
    catch (JackException e) {
      throw new RuntimeException("Failed to connect JACK outputs", e);
    }
  }


  /*
  private void connectToSystemOutputs() {
   try {
   String[] ports = Jack.getInstance().getPorts(
   client,
   "system:.*",
   JackPortType.AUDIO,
   EnumSet.of(JackPortFlags.JackPortIsInput)
   );
   
   if (ports == null || ports.length == 0) {
   System.err.println("No JACK system playback ports found");
   return;
   }
   
   for (int i = 0; i < Math.min(outputPorts.size(), ports.length); i++) {
   Jack.getInstance().connect(
   client,
   outputPorts.get(i).getName(),
   ports[i]
   );
   }
   }
   catch (JackException e) {
   throw new RuntimeException("Failed to connect JACK outputs", e);
   }
   }
   */
  /*
  private void connectToSystemOutputs() {
   try {
   String[] ports = Jack.getInstance().getPorts(
   client,
   null, // match all names
   JackPortType.AUDIO,
   EnumSet.of(
   JackPortFlags.JackPortIsInput,
   JackPortFlags.JackPortIsPhysical
   )
   );
   
   if (ports == null || ports.length == 0) {
   System.err.println("No physical JACK playback ports found");
   return;
   }
   
   for (int i = 0; i < Math.min(outputPorts.size(), ports.length); i++) {
   Jack.getInstance().connect(
   client,
   outputPorts.get(i).getName(),
   ports[i]
   );
   }
   }
   catch (JackException e) {
   throw new RuntimeException("Failed to connect JACK outputs", e);
   }
   }
   */

  // =====================================================
  private boolean firstRun = true;

  @Override
    public boolean process(JackClient client, int nframes) {

    // PipeWire/JACK may legally call this with 0
    if (nframes <= 0) {
      return true;
    }

    if (firstRun) {
      System.err.println("JACK process callback running");
      firstRun = false;
    }

    // Lazy buffer allocation / resize
    if (backendBuffers == null || backendBuffers[0].length != nframes) {
      bufferSize = nframes;
      backendBuffers = new float[channels][bufferSize];
    }

    // Always clear outputs first (safe silence)
    for (JackPort port : outputPorts) {
      FloatBuffer fb = port.getFloatBuffer();
      fb.rewind();
      for (int i = 0; i < nframes; i++) {
        fb.put(0f);
      }
    }

    // If engine not active yet, we are done
    if (!outputActive || callback == null) {
      return true;
    }

    // Run engine
    callback.process(
      backendBuffers,
      bufferSize,
      System.nanoTime(),
      samplePosition
      );

    // Write engine output
    for (int c = 0; c < channels; c++) {
      FloatBuffer fb = outputPorts.get(c).getFloatBuffer();
      fb.rewind();
      fb.put(backendBuffers[c], 0, nframes);
    }

    samplePosition += nframes;
    return true;
  }


  // =====================================================
  @Override
    public void start() {
      println(">>> JackBackend.start() CALLED");
    try {
      client.activate();        // ports become real here
      connectToSystemOutputs(); // now ports actually exist
      outputActive = true;      // NOW engine audio is allowed
    }
    catch (JackException e) {
      throw new RuntimeException("Failed to activate JACK client", e);
    }
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
