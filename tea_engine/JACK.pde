/*
Uses: https://github.com/jaudiolibs/jnajack
 before running the app start JACK:
 jackd
 
 pipewire PopOS for example and modern Linux distros)
 sudo apt update
 sudo apt install pipewire-jack jackd2 (or sudo apt install pipewire-jack)
 no need to set realtime privilieges (you can select no)
 verify you have pipewire installed and running:
 pw-jack jack_lsp
 
 this is already included in modified launcher inside the release - see original for comparison.
 //to run processing IDE though JACK using pipewire without exporting app:
 //pw-jack processing
 //when bulding you cant simply run processsing with pw-jack when using flatpack due to sandboxing...but it works once you export the app as standalone built
 //flatpack does not accept input parameters :-(
 
 TBD
 in list device names at least i can show jak ports sorted by prefix
 but i will use speakerpreset to link them to channels
 get rid of connectToSystemOutputs replace with connectPorts
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
class JackBackend extends AbstractAudioBackend implements AudioBackend, JackProcessCallback {

  //JACK uses semnantic output mapping, we can reuse speaker preset for this using "label" property to match the output name
  private String saveJsonDir = "speaker_presets";
  private Preset speakerPreset;

  private final Map<Integer, JackPort> channelPorts = new HashMap<>(); //preserve preset order to keep consistent with ASIO and CorAudio

  private JackClient client;
  private final List<JackPort> outputPorts = new ArrayList<>();

  private long samplePosition = 0;
  private static final String JACK_AUDIO_TYPE ="32 bit float mono audio";

  public void setSpeakerPreset(Preset preset) {
    this.speakerPreset = preset;
  }
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
      active = false;

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
  private List<String> getJackInputPorts() {
    try {
      String[] ports = Jack.getInstance().getPorts(
        client,
        null,
        JackPortType.AUDIO,
        EnumSet.of(JackPortFlags.JackPortIsInput)
        );
      return ports == null ? List.of() : Arrays.asList(ports);
    }
    catch (JackException e) {
      return List.of();
    }
  }
  // =====================================================
  private void connectPorts() {

    if (speakerPreset == null || speakerPreset.speakers.isEmpty()) {
      System.err.println("No speaker preset set for JACK backend");
      return;
    }

    outputPorts.clear();
    channelPorts.clear();

    channels = speakerPreset.speakers.size();

    // Sort speakers by index to guarantee channel order
    List<Speaker> ordered = new ArrayList<>(speakerPreset.speakers);
    ordered.sort(Comparator.comparingInt(s -> s.index));

    List<String> jackInputs = getJackInputPorts();

    for (Speaker s : ordered) {

      try {
        // 1. Create logical output port for this channel
        JackPort out = client.registerPort("out_" + s.index + "_" + s.label, JackPortType.AUDIO, EnumSet.of(JackPortFlags.JackPortIsOutput));
        outputPorts.add(out);
        channelPorts.put(s.index, out);

        // 2. Resolve destination using label
        String label = s.label.toLowerCase();
        Optional<String> match = jackInputs.stream().filter(p -> p.toLowerCase().contains(label)).findFirst();
        if (match.isEmpty()) {
          println("JACK: no destination found for speaker [" + s.label + "]");
          continue;
        }
        // 3. Connect
        Jack.getInstance().connect(client, out.getName(), match.get());
      }
      catch (JackException e) {
        println("JACK: failed to connect "+s.index +":"+s.label);
      }
    }
  }
  // =====================================================

  public void exportOutputs() {

    List<String> jackOutputs = getJackInputPorts(); // JACK inputs = destinations

    JSONArray speakers = new JSONArray();

    for (int i = 0; i < jackOutputs.size(); i++) {
      String port = jackOutputs.get(i);
      JSONObject s = new JSONObject();
      s.setInt("index", i);
      s.setString("label", port);   // full port name, user can shorten later
      s.setBoolean("lfe", false);
      JSONArray position = new JSONArray();
      position.setFloat(0, 0);
      position.setFloat(1, 0);
      position.setFloat(2, 0);
      s.setJSONArray("position_normalized", position);
      speakers.setJSONObject(i, s);
    }

    JSONObject root = new JSONObject();
    root.setString("name", "JACK Outputs");
    root.setJSONArray("speakers", speakers);
    saveJSONObject(root, rootFolder+File.separator+saveJsonDir+"jack_outputs_preset.json");
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

  // =====================================================
  @Override
    public boolean process(JackClient client, int nframes) {

    // PipeWire/JACK may legally call this with 0
    if (nframes <= 0) {
      return true;
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
    if (!active || callback == null) {
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
      active = true;      // NOW engine audio is allowed
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
    active = false;
  }

  // =====================================================
  @Override
    public void setCallback(AudioCallback cb) {
    this.callback = cb;
  }

  @Override
    public boolean isActive() {
    return active;
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
    // JACK has one logical device (the server), there is no "output device" just individual channels (in JACK terminology ports)
    //so every port is alway mono...this is different concept compared to ASIO and CoreAudio 
    //I am making use speaker preset to assing the ports to channels
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
