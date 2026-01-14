import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import peasy.PeasyCam;
import com.krab.lazy.*;
import ch.section6.jcoreaudio.*;
import java.nio.FloatBuffer;
import java.util.*;
import java.io.File;
import java.nio.file.Paths;
import java.util.*;
import io.jhdf.HdfFile;
import io.jhdf.api.Dataset;
import java.util.List;
import org.jtransforms.fft.FloatFFT_1D;
import java.util.function.Consumer;
import java.util.ArrayList;
import java.util.List;
import java.util.Set;
import org.jaudiolibs.jnajack.*;
import java.util.*;
import java.nio.FloatBuffer;
import java.util.EnumSet;
import java.util.List;
import org.jaudiolibs.jnajack.lowlevel.JackLibrary;
import com.sun.jna.Pointer;
import java.util.HashMap; // import the HashMap class
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.Comparator;
import java.util.Collections;
import java.util.Arrays;
import javax.sound.sampled.*;
import java.io.File;
import java.io.IOException;
import java.util.HashMap;
import java.util.*; //for Vector type
import java.util.HashMap; // import the HashMap class
import oscP5.*;
import netP5.*;
import java.net.InetAddress;
import javax.sound.sampled.AudioFormat;
import java.io.File;
import java.io.FileOutputStream;
import java.io.BufferedOutputStream;
import java.io.OutputStream;
import java.io.RandomAccessFile;
import java.io.IOException;
import java.util.concurrent.ConcurrentLinkedQueue;
import TUIO.*;
import javax.swing.JFileChooser;
import java.io.File;
import java.nio.file.Files;
import java.nio.file.Paths;
import java.util.Arrays;
import java.awt.Desktop;
import javax.sound.sampled.*;

import processing.core.*;
import processing.data.*;
import processing.event.*;
import processing.opengl.*;
import java.util.HashMap;
import java.util.ArrayList;
import java.io.File;
import java.io.BufferedReader;
import java.io.PrintWriter;
import java.io.InputStream;
import java.io.OutputStream;
import java.io.IOException;

/** Processing Sketch tea_engine */
public class tea_engine {
/*
 ©2025 Vojtech Leischner
 Creative Commons Attribution-NonCommercial-ShareAlike 4.0 International (CC BY-NC-SA 4.0).
 When using or distributing the code, give credit in the form of "Trick the Ear Audio Engine software (https://github.com/trackme518/trick-the-ear-spatial-audio-engine) by Vojtech Leischner (https://trackmeifyoucan.com)".
 
 Please refer to the license at https://creativecommons.org/licenses/by-nc-sa/4.0/.
 
 The author is not liable for any damage caused by the software.
 Usage of the software is completely at your own risk.
 For commercial licensing, please contact us.
 */


String windowTitle = "Trick the Ear - Audio Engine v1.0";


AudioEngine host;
//AsioHost host;
PApplet context;

PeasyCam cam;

LazyGui gui;

float fps = 0; //running average
//------------------------------
String[] playbackModes = {"play once", "play all", "loop one", "loop all"};
String[] generatePresetModes = {"circular", "rectangular"};
int playbackModeInt = 1; //default "play all"
boolean syncRecToPlay = false;
//---------------------

PGraphics canvas; //offscreen render texture for 3D speakers visualization
SpatialAudio spatialEngine;
PresetGenerator presetGenerator;

int _width, _height; //keep track of sketch dimensions in case of resize event

void setup() {
  size(1280, 1024, P2D);
  pixelDensity(displayDensity());
  context = this;
  //surface.setTitle(windowTitle);
  frameRate(500);

  canvas = createGraphics(width, height, P3D);

  presetGenerator = new PresetGenerator();
  spatialEngine = new SpatialAudio();

  host = new AudioEngine();
  //host = new AsioHost();

  gui = new LazyGui(this);
  gui.hide("options");

  osc = new Osc();
  tuioClient  = new TuioProcessing(this);

  loadingStatus = new Loading();

  cam = new PeasyCam(this, 1200);
  cam.setMinimumDistance(10);
  cam.setMaximumDistance(10000);
}

void checkResize() {
  if (width != _width || height !=  _height) {
    _width = width;
    _height = height;
    canvas = createGraphics(width, height, P3D);
    cam = new PeasyCam(this, 1200);
  }
}


void draw() {
  //---------------------------------
  background(0);

  //move some of the file loading into draw at later stage - sometimes when setup() is taking too long it crashes
  loadingStatus.update();
  if ( !loadingStatus.initialized) {
    return;
  }

  //==================Record GUI======================================
  gui.pushFolder("recorder");
  if (host.recordingEnabled) {
    gui.colorPickerSet("recording", color(255, 0, 0));
  } else {
    gui.colorPickerSet("recording", color(127));
  }

  //simultounasly start recording and playback
  syncRecToPlay = gui.toggle("sync to play", false);

  if (gui.button("start")) {
    if (syncRecToPlay) {
      playlists.playlist.play();
    }
    host.startRecording();
  }
  if (gui.button("stop")) {
    if (syncRecToPlay) {
      playlists.playlist.stop();
    }
    host.stopRecording();
  }
  if (gui.button("open folder")) {
    openFolder(host.lastRecordingPath );
  }

  host.recordingChannels = gui.sliderInt("channels:", host.recordingChannels, 1, 128);
  gui.popFolder();

  //==================Output GUI======================================
  gui.pushFolder("output");
  String currDeviceName = gui.radio("device", host.deviceNames );
  host.binaural = gui.toggle("binaural", host.binaural);

  if (gui.button("open")) {
    host.open(currDeviceName); //will call backend
  }
  gui.sliderSet("outputs:", host.backend.getOutputChannelCount());
  gui.toggleSet("active", host.backend.isActive() );

  if (gui.button("close")) {
    host.backend.close();
  }

  if (gui.button("restart")) {
    host.backend.resetRequest();
  }

  if (gui.button("control panel")) {
    host.backend.openControlPanel();
  }

  boolean isTestingMode = gui.toggle("test noise", false);
  host.setTestSound( isTestingMode );
  host.setTestingChannel( gui.sliderInt("channel index", 0, 0, 128 ) );

  gui.pushFolder("subwoofers");
  host.applyLowpass = gui.toggle("lowpass", host.applyLowpass);

  int subCount = gui.sliderInt("count", 1, 1, 16);

  float currCutoff = gui.slider("cuttoff", 120, 0, 250);
  if (host.subLowpass!=null) {
    if ( host.subLowpass.cutoff !=  currCutoff) {
      host.subLowpass.setCutoff(currCutoff);
      println("set lowpass cutoff at "+currCutoff);
    }
  }

  float bassVolume = gui.slider("bass volume", 0.99, 0.1, 5.0);
  if (host.subLowpass!=null) {
    host.subLowpass.setVolume( bassVolume );
  }

  for (int i=0; i<subCount; i++) {
    int channelIndex = gui.sliderInt("sub_"+i+"/channel", 0, 0, 64 );//-1 means disabled

    if (host.outputBuffers.size() > 0) {
      if (channelIndex>=host.outputBuffers.size()-1) {
        gui.sliderSet("sub_"+i+"/channel", host.outputBuffers.size()-1);
        break;
      }
    }

    if ( host.subChannels.size()<=i ) {
      host.subChannels.add( channelIndex );
      gui.show("sub_"+i);
    } else {
      host.subChannels.set(i, channelIndex); //immutable
    }
  }
  if (subCount<host.subChannels.size()) {
    // remove extra speakers if subCount decreased
    while (host.subChannels.size() > subCount) {
      int index = host.subChannels.size() - 1;
      //println("removing "+index);
      host.subChannels.remove(index);
      gui.hide("sub_"+index);
    }
  }
  gui.popFolder(); //end subwoofers
  gui.popFolder(); //end output
  //==================Playback GUI======================================

  //select playlist
  //String currPlaylist = gui.radio("playlist", new String[]{"square", "circle", "triangle"}, "square");
  String currPlaylist = gui.radio("playback/playlist", playlists.playlistsNames, playlists.playlist.name);

  if ( !currPlaylist.equals(playlists.prevPlaylistName) ) {
    Playlist newPlaylist = playlists.getPlaylistByName(currPlaylist);
    if (newPlaylist!=null) { //check that such playlist exists in the avaliable options
      boolean playbackStarted = playlists.playlist.isPlaying; //remember if we are currently playing
      playlists.playlist.stop(); //stop previous preset first
      println("old playlist: "+playlists.playlist.name);
      //hide previous GUI states
      for (int t=0; t< playlists.playlist.samples.size(); t++) {
        Track track = playlists.playlist.samples.get(t);

        println(gui.getFolder());
        gui.hide("Tracks/"+track.name); //this affects on the root level since i did not use pushFolder("x") before here
        println("hide "+track.name);
      }

      playlists.playlist = newPlaylist; //assgin selected playlist
      playlists.prevPlaylistName = currPlaylist;
      println("new playlist: "+playlists.playlist.name);
      if (playbackStarted) { //if we were playing the previous playing. strat playing the new one instantly
        playlists.playlist.play();
      }
    }
  }

  gui.pushFolder("playback");

  if ( gui.button("play") ) {
    playlists.playlist.play();
  }
  //-----
  if ( gui.button("stop") ) {
    playlists.playlist.stop();
  }
  //-----
  if ( gui.button("pause")) {
    playlists.playlist.pause();
  }
  //------
  float currVolume = gui.slider("volume", 0.750, 0.0, 1.0);
  host.setVolume(currVolume);

  //------
  String playbackModeString = gui.radio("loop", playbackModes, playbackModes[playbackModeInt] );
  for (int i=0; i<playbackModes.length; i++) {
    if (playbackModeString.equals(playbackModes[i]) ) {
      playbackModeInt = i;
    }
  }

  boolean _loopStems = gui.toggle("loop stems", playlists.playlist.loopStems);
  if (playlists.playlist.loopStems != _loopStems) {
    playlists.playlist.setLoopStems(_loopStems);
  }

  //provide user with two options to set the root folder - by copy paste into text field / manual typing
  gui.textSet("playlists root", playlists.rootFolder);
  //using file explorer picker
  if (gui.button("choose folder") ) {
    // Assign callback to the function
    selectFolder((File newDir) -> {
      if (newDir != null) {
        playlists.rootFolder = newDir.getAbsolutePath();
        playlists.loadPlaylists();
        // Safe GUI update
        gui.radioSetOptions("playback/playlist", playlists.playlistsNames);
        gui.radioSet("playback/playlist", playlists.playlist.name);
        println("Default playlist folder set to " + newDir.getAbsolutePath());
      } else {
        println("Folder selection canceled.");
      }
    }
    );
  }

  if (gui.button("scan folder") ) {
    playlists.loadPlaylists();
    gui.radioSetOptions("playback/playlist", playlists.playlistsNames);
    gui.radioSet("playback/playlist", playlists.playlist.name);
  }


  gui.popFolder();

  //==================OSC GUI======================================
  gui.pushFolder("OSC");
  int _currOscPort = PApplet.parseInt( gui.slider("listen port", osc.oscPort) );
  if ( _currOscPort != osc.oscPort) {
    println("set osc port");
    osc.setPort( _currOscPort );
  }
  gui.popFolder();

  //==================Tracks GUI======================================

  //enable user control when switched to manual - good for debugging
  //!warning - subwoofer channel is NOT affected as it gets calculated directly in host...maybe i can fix this later
  gui.pushFolder("Tracks" );
  for (int t=0; t< playlists.playlist.samples.size(); t++) {
    Track track = playlists.playlist.samples.get(t);

    gui.show(track.name);
    //if ( track.gains !=null) {
    gui.pushFolder(track.name);

    boolean manualControl = gui.toggle("manual", false); //enable user to set individual gains for each channel by hand
    track.mute = gui.toggle( "mute", track.mute);

    track.isStatic = gui.toggle("static", track.isStatic);
    track.spatial = gui.toggle("spatial", track.spatial);


    String animateMode = gui.radio("animate", track.virtualSource.motionModeNames, track.virtualSource.motionMode );
    if (!animateMode.equals( track.virtualSource.motionMode )) {
      track.virtualSource.setMotionMode(animateMode);
    }
    track.virtualSource.drawGui();


    if (track.isStatic) { //let user set the position via GUI
      PVector tPos = track.getPosition();
      PVector _currPlotPos =  gui.plotXYZ("position", tPos.x, tPos.y, tPos.z);
      track.setPosition( _currPlotPos );
    } else {
      gui.plotSet("position", track.getPosition() ); //just show
    }


    for (int i=0; i< 128; i++) {
      String guiPath = "gain_"+ i;
      //String guiPath = "Tracks/"+track.name+"gain_"+ i;
      if (i<host.outputBuffers.size()) {
        //for (int i=0; i< host.activeChannels.size(); i++) {
        gui.show(guiPath);
        if (manualControl) {
          float gain = gui.slider(guiPath, 0.001);
          //track.gains.put(i, gain);
          track.setGain(i, gain);
        } else {

          //float gain = track.gains.getOrDefault(i, 0.001);//set default to 0.001 to keep precision :-/
          float gain = track.getGain(i);
          gui.sliderSet(guiPath, gain);
        }
      } else {
        gui.hide(guiPath);
      }
    }
    gui.popFolder(); //end for each Track
    //}
  }
  gui.popFolder();//end for all Tracks

  //==================Spatial Audio GUI======================================

  gui.pushFolder("Spatial Engine");
  String selectedPresetName = gui.radio("preset:", spatialEngine.presetNames, spatialEngine.preset.name );
  //if (!gui.isMouseOutsideGui() ) {//only when hovering over GUI - it collided with OSC API
  if ( !selectedPresetName.equals(spatialEngine.preset.name) ) { //on change hack
    spatialEngine.getPresetByName( selectedPresetName ); //use selected preset
    //flock1.set2D(spatialEngine.preset.is2D);
  }

  spatialEngine.showConvexHull = gui.toggle("show hull", spatialEngine.showConvexHull);
  spatialEngine.powerSharpness = gui.slider("sharpness", spatialEngine.powerSharpness, 1, 5);
  spatialEngine.selectionBias = gui.slider("stickiness", spatialEngine.selectionBias, 0.0f, 0.5);

  //----------------------------------------
  //generate new preset with dynamic functions - see SpatialEngine tab
  gui.pushFolder("generate");
  String selectedPresetMode = gui.radio("mode", generatePresetModes, "circular" ); //global var see generatePresetModes
  if (!selectedPresetMode.equals(presetGenerator.mode) ) {
    presetGenerator.toggleGui(false);
    presetGenerator.setMode(selectedPresetMode);
    presetGenerator.toggleGui(true);
  }
  presetGenerator.drawGui();
  gui.popFolder();
  //----------------------------------------

  String spatialMode = gui.radio("spatial mode", new String[]{"dot product", "euclidian"}, "euclidian");
  if (spatialMode.equals("dot product")) {
    spatialEngine.mode = spatialEngine.DOT_PRODUCT;
  } else {
    spatialEngine.mode = spatialEngine.EUCLIDIAN;
  }
  gui.popFolder();

  //==================RENDER DRAW LOOP ======================================

  canvas.beginDraw();
  canvas.clear();
  for (Track t : playlists.playlist.samples) {
    t.update(); //updates virtual audio source internally + render visualization
  }
  canvas.endDraw();

  spatialEngine.render(canvas); //it will intrenally check for preset change as well
  cam.getState().apply(canvas);

  image(canvas, 0, 0);

  playlists.playlist.update();
  renderTimeline();

  //----------------------------------------
  fps = approxRollingAverage(fps, frameRate, 30);
  surface.setTitle(windowTitle+" fps: "+PApplet.parseInt(fps) );
  osc.checkConnection();
  osc.renderIcon();



  cam.beginHUD(); // makes the gui visual exempt from the PeasyCam controlled 3D scene
  gui.draw(); // displays the gui manually here - rather than automatically when draw() ends
  cam.endHUD();
  // PeasyCam ignores mouse input while the mouse interacts with the GUI
  cam.setMouseControlled(gui.isMouseOutsideGui());

  checkResize();
}


void exit() {
  println("app clean exit");
  //close ASIO driver if it is running
  host.backend.close();
  super.exit();
}

//-----------------------------------
void renderTimeline() {
  //strokeWeight(3);
  text(playlists.playlist.name, 50, height-50);
  stroke(255);
  noFill();
  line(50, height-50, width-50, height-50);
  //duration
  float currPos = playlists.playlist.pos;
  float duration = playlists.playlist.duration;
  float posX = map(currPos, 0, duration, 50, width-50);
  ellipse(posX, height-50, 30, 30);
}
//-----------------------------------
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
}/*
Uses: https://github.com/mhroth/JCoreAudio/tree/master
Include JCoreAudio.jar in your Java project.
Make libJCoreAudio.jnilib available to your project. This can be done in several ways:
Move or copy the library to /Library/Java/Extensions. This is the default search location for JNI libraries.
Inform the JVM where the library is located. This can be done with, e.g. java -Djava.library.path=/Library/Java/Extensions

JCoreAudio is licensed under a modified LGPL with a non-commercial clause, in the spirit of the Creative Commons Attribution-NonCommercial (CC BY-NC) license. 
Anyone wishing to use JCoreAudio commercially should contact me directly.

*/


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
// HeadRelated Transfer Function - create stereo for monitoring spatial audio with headphones
//completely different to VBAN
// -----------------------------



SharedHrtfContext sharedHRTF;


public interface HrtfReadyCallback {
  void onReady(SharedHrtfContext ctx);
  void onError(Exception e);
}

public class SharedHrtfContext {
  // SH order
  public final int L = 5;
  public final int K = (L + 1) * (L + 1); // 36 coefficients for L=5

  public HrirInterpolatorSH interpolator;

  public final Map<PVector, float[]> irFreqL = new HashMap<>();
  public final Map<PVector, float[]> irFreqR = new HashMap<>();

  public int fftSize;
  FloatFFT_1D fft;
  public int irLength;
  public int bufferSize;

  private volatile boolean ready = false;

  public SharedHrtfContext(int bufferSize, Consumer<SharedHrtfContext> onReady) {
    this.bufferSize = bufferSize;

    // fire async loading
    new Thread(() -> {
      try {
        loadAsync();
        ready = true;
        if (onReady != null) onReady.accept(this);
      }
      catch (Exception e) {
        println("Failed loading HRIR SOFA for HRTF inside SharedHrtfContext class: "+e);
        ready = false;
        //if (onError != null) onError.accept(e);
      }
    }
    , "HRTF-Loader").start();
  }

  private void loadAsync() throws Exception {

    String hrirFolder = dataPath("HRIR");
    File dir = new File(hrirFolder);
    File[] sofaFiles = dir.listFiles((d, name) -> name.toLowerCase().endsWith(".sofa"));

    if (sofaFiles == null || sofaFiles.length == 0) {
      throw new RuntimeException("No SOFA files found in " + hrirFolder);
    }

    interpolator = new HrirInterpolatorSH();

    String sofaPath = sofaFiles[0].getAbsolutePath();
    System.out.println("Loading HRIRs from: " + sofaPath);

    Map<PVector, float[]> hrirLtmp = new HashMap<>();
    Map<PVector, float[]> hrirRtmp = new HashMap<>();

    irLength = loadHRIRsFromSofa(sofaPath, hrirLtmp, hrirRtmp);

    int fftSz = 1;
    while (fftSz < bufferSize + irLength - 1) fftSz <<= 1;
    fftSize = fftSz;

    fft = new FloatFFT_1D(fftSize);

    precomputeIrFreq(hrirLtmp, irFreqL, fftSize);
    precomputeIrFreq(hrirRtmp, irFreqR, fftSize);

    interpolator.fitSH(irFreqL, irFreqR, fftSize);

    System.out.println(
      "SharedHrtfContext ready. FFT size=" + fftSize + ", IR length=" + irLength
      );
  }

  /*
  public SharedHrtfContext(int bufferSize) {
   this.bufferSize = bufferSize;
   
   // Load SOFA file
   String hrirFolder = dataPath("HRIR");
   File dir = new File(hrirFolder);
   File[] sofaFiles = dir.listFiles((d, name) -> name.toLowerCase().endsWith(".sofa"));
   
   if (sofaFiles == null || sofaFiles.length == 0) {
   println("No SOFA files found in " + hrirFolder);
   }
   
   this.interpolator = new HrirInterpolatorSH();
   
   String sofaPath = sofaFiles[0].getAbsolutePath();
   System.out.println("Loading HRIRs from: " + sofaPath);
   
   Map<PVector, float[]> hrirLtmp = new HashMap<>();
   Map<PVector, float[]> hrirRtmp = new HashMap<>();
   int irLenTmp = loadHRIRsFromSofa(sofaPath, hrirLtmp, hrirRtmp);
   
   this.irLength = irLenTmp;
   
   // Compute fftSize based on buffer + IR length
   int fftSz = 1;
   while (fftSz < bufferSize + irLength - 1) fftSz <<= 1;
   this.fftSize = fftSz;
   
   this.fft = new FloatFFT_1D(fftSize);
   
   // Precompute FFT HRIRs
   precomputeIrFreq(hrirLtmp, irFreqL, fftSize);
   precomputeIrFreq(hrirRtmp, irFreqR, fftSize);
   
   // Fit SH
   interpolator = new HrirInterpolatorSH();
   try {
   interpolator.fitSH(irFreqL, irFreqR, fftSize);
   }
   catch(Exception e) {
   println(e);
   return;
   }
   System.out.println("SharedHrtfContext ready. FFT size=" + fftSize + ", IR length=" + irLength);
   }
   */

  private void precomputeIrFreq(Map<PVector, float[]> hrirTime, Map<PVector, float[]> irFreq, int fftSize) {


    for (Map.Entry<PVector, float[]> entry : hrirTime.entrySet()) {
      PVector key = entry.getKey();
      float[] h = entry.getValue();
      float[] freq = new float[2 * fftSize];
      for (int i = 0; i < h.length; i++) {
        freq[2 * i] = h[i];
        freq[2 * i + 1] = 0f;
      }
      fft.complexForward(freq);
      irFreq.put(key, freq);
    }
  }

  private int loadHRIRsFromSofa(String sofaPath, Map<PVector, float[]> hrirL, Map<PVector, float[]> hrirR) {
    try (HdfFile sofaFile = new HdfFile(Paths.get(sofaPath))) {
      Dataset dataIR = sofaFile.getDatasetByPath("Data.IR");
      double[][][] irDouble = (double[][][]) dataIR.getData(); // [M,R,N]
      float[][][] irFloat = toFloat(irDouble);

      Dataset sourcePos = sofaFile.getDatasetByPath("SourcePosition");
      double[][] spDouble = (double[][]) sourcePos.getData();
      float[][] sp = toFloat(spDouble);

      int irLen = 0;
      for (int i = 0; i < irFloat.length; i++) {
        float az = sp[i][0];
        float el = sp[i][1];
        PVector key = new PVector(az, el);
        hrirL.put(key, irFloat[i][0]);
        hrirR.put(key, irFloat[i][1]);
        if (irLen == 0) irLen = irFloat[i][0].length;
      }
      System.out.println("Loaded " + irFloat.length + " HRIRs from SOFA.");
      return irLen;
    }
    catch(Exception e) {
      println("can't load HRIRs from SOFA file. "+e);
      return 0;
    }
  }

  private float[][][] toFloat(double[][][] arr) {
    int d1 = arr.length, d2 = arr[0].length, d3 = arr[0][0].length;
    float[][][] out = new float[d1][d2][d3];
    for (int i = 0; i < d1; i++)
      for (int j = 0; j < d2; j++)
        for (int k = 0; k < d3; k++)
          out[i][j][k] = (float) arr[i][j][k];
    return out;
  }

  private float[][] toFloat(double[][] arr) {
    int r = arr.length, c = arr[0].length;
    float[][] out = new float[r][c];
    for (int i = 0; i < r; i++)
      for (int j = 0; j < c; j++)
        out[i][j] = (float) arr[i][j];
    return out;
  }
}
//------------------------------------------------------------------------------------------------

// -----------------------------
// BinauralAudioProcessor.java
// -----------------------------

public class BinauralAudioProcessor {

  //--------------------------------------------
  private SharedHrtfContext sharedHRTF;

  // Source position
  public volatile float currentAzimuth = 0;
  public volatile float currentElevation = 0;

  // Audio overlap-add buffers
  private float[] overlapL;
  private float[] overlapR;
  FloatFFT_1D fft;

  public BinauralAudioProcessor(SharedHrtfContext sharedHRTF) throws Exception {
    this.sharedHRTF = sharedHRTF;
    this.fft = new FloatFFT_1D(sharedHRTF.fftSize); //per-track FFT

    this.overlapL = new float[sharedHRTF.fftSize - sharedHRTF.bufferSize];
    this.overlapR = new float[sharedHRTF.fftSize - sharedHRTF.bufferSize];
    Arrays.fill(this.overlapL, 0);
    Arrays.fill(this.overlapR, 0);
  }

  //---------------- Source positioning ----------------
  public void setPositionPolar(float azimuth360, float sourceElevation) {
    this.currentAzimuth = azimuth360;
    this.currentElevation = sourceElevation;
  }

  public void setPosition(PVector pos) {
    float sourceAzimuth = (float) Math.toDegrees(Math.atan2(pos.z, pos.x));
    float azimuth360 = (sourceAzimuth < 0) ? sourceAzimuth + 360 : sourceAzimuth;
    float sourceElevation = (float) Math.toDegrees(Math.atan2(pos.y, Math.sqrt(pos.x*pos.x + pos.z*pos.z)));
    setPositionPolar(azimuth360, sourceElevation);
  }

  //---------------- Audio processing ----------------
  public float[][] process(float[] inputBuffer) {
    float[] outL = new float[inputBuffer.length];
    float[] outR = new float[inputBuffer.length];
    fftConvolve(inputBuffer, outL, outR, this.currentAzimuth, this.currentElevation);
    return new float[][] { outL, outR };
  }

  private void fftConvolve(float[] inputBuffer, float[] outputL, float[] outputR, float az, float el) {

    // Prepare zero-padded input FFT buffer
    float[] inputFFT = new float[2 * sharedHRTF.fftSize];
    Arrays.fill(inputFFT, 0f);

    /*
    for (int i = 0; i < sharedHRTF.bufferSize; i++) {
     inputFFT[2 * i] = inputBuffer[i];
     inputFFT[2 * i + 1] = 0;
     }
     */

    int framesToCopy = Math.min(inputBuffer.length, sharedHRTF.bufferSize);
    for (int i = 0; i < framesToCopy; i++) {
      inputFFT[2 * i] = inputBuffer[i];
    }


    // Forward FFT
    this.fft.complexForward(inputFFT);

    // Interpolate HRIR spectrum
    float[][] irFreq = sharedHRTF.interpolator.reconstructComplexSpectrum(az, el);
    float[] irLFreq = irFreq[0];
    float[] irRFreq = irFreq[1];

    // Frequency-domain multiplication
    float[] convFreqL = new float[2 * sharedHRTF.fftSize];
    float[] convFreqR = new float[2 * sharedHRTF.fftSize];

    for (int i = 0; i < sharedHRTF.fftSize; i++) {
      int re = 2 * i;
      int im = re + 1;

      convFreqL[re] = inputFFT[re] * irLFreq[re] - inputFFT[im] * irLFreq[im];
      convFreqL[im] = inputFFT[re] * irLFreq[im] + inputFFT[im] * irLFreq[re];

      convFreqR[re] = inputFFT[re] * irRFreq[re] - inputFFT[im] * irRFreq[im];
      convFreqR[im] = inputFFT[re] * irRFreq[im] + inputFFT[im] * irRFreq[re];
    }

    // Inverse FFT
    this.fft.complexInverse(convFreqL, true);
    this.fft.complexInverse(convFreqR, true);

    // Overlap-add
    /*
    for (int i = 0; i < sharedHRTF.bufferSize; i++) {
     float overlapValL = (i < this.overlapL.length) ? this.overlapL[i] : 0f;
     float overlapValR = (i < this.overlapR.length) ? this.overlapR[i] : 0f;
     outputL[i] = convFreqL[2 * i] + overlapValL;
     outputR[i] = convFreqR[2 * i] + overlapValR;
     }
     */


    // Overlap-add to output
    for (int i = 0; i < framesToCopy; i++) {
      outputL[i] = convFreqL[2 * i] + ((i < overlapL.length) ? overlapL[i] : 0f);
      outputR[i] = convFreqR[2 * i] + ((i < overlapR.length) ? overlapR[i] : 0f);
    }


    // Update overlap buffers safely
    Arrays.fill(this.overlapL, 0);
    Arrays.fill(this.overlapR, 0);

    for (int i = 0; i < overlapL.length; i++) {
      this.overlapL[i] = convFreqL[2 * (i + sharedHRTF.bufferSize)];
      this.overlapR[i] = convFreqR[2 * (i + sharedHRTF.bufferSize)];
    }

    int safeOverlap = Math.min(overlapL.length, sharedHRTF.fftSize - framesToCopy);
    for (int i = 0; i < safeOverlap; i++) {
      overlapL[i] = convFreqL[2 * (i + framesToCopy)];
      overlapR[i] = convFreqR[2 * (i + framesToCopy)];
    }
  }
}
// ---------- helper for BinauralAudioProcessor (HRTF tab) - spehrical harmonics interpolation of HRIRs ----------
// import statements near top of file:

// Put this inner class in place of your old HrirInterpolator
public class HrirInterpolatorSH {
  // SH order
  private final int L = 5;           // order
  private final int K = (L + 1) * (L + 1); // 36 coeffs for L=5

  // precomputed design matrix and inverse ATA
  // A: M x K (M = 0xmeasurements)
  private double[][] A;         // M x K (double)
  private double[][] ATAinv;    // K x K inverse of A^T A
  private int M;                // number of measurements
  private List<PVector> dirs;   // measurement directions (az,el) in degrees, length M

  // SH coefficients per frequency and ear:
  // coeffsRealLeft[freq][k], coeffsImagLeft[freq][k]
  private float[][] coeffsRealL;
  private float[][] coeffsImagL;
  private float[][] coeffsRealR;
  private float[][] coeffsImagR;

  private int fftSize = 0;

  // ---------- public API ----------
  // Fit SH coeffs from frequency-domain complex HRIR maps
  // irFreqL and irFreqR maps: keys = PVector(az,el), value = float[2*fftSize] (complex interleaved)
  // fftSize is the number of complex bins (not the length of time IR)
  public void fitSH(Map<PVector, float[]> irFreqL, Map<PVector, float[]> irFreqR, int fftSizeIn) throws Exception {
    this.fftSize = fftSizeIn;
    // Build direction list and M
    dirs = new ArrayList<>();
    for (PVector k : irFreqL.keySet()) {
      dirs.add(new PVector(k.x, k.y)); // only (az,el)
    }
    M = dirs.size();

    if (M == 0) {
      throw new IllegalArgumentException("No measurement directions found for SH fit");
    }

    // Build A matrix (M x K)
    A = new double[M][K];
    for (int i = 0; i < M; i++) {
      double[] Y = evalRealSHVector(dirs.get(i).x, dirs.get(i).y); // length K
      System.arraycopy(Y, 0, A[i], 0, K);
    }

    // Compute ATA = A^T * A (K x K)
    double[][] ATA = new double[K][K];
    for (int a = 0; a < K; a++) {
      for (int b = 0; b < K; b++) {
        double s = 0.0;
        for (int i = 0; i < M; i++) s += A[i][a] * A[i][b];
        ATA[a][b] = s;
      }
    }

    // Invert ATA (K x K)
    ATAinv = invertMatrix(ATA);
    if (ATAinv == null) throw new Exception("Failed to invert ATA matrix for SH fit");

    // Allocate coefficient arrays: fftSize x K
    coeffsRealL = new float[fftSize][K];
    coeffsImagL = new float[fftSize][K];
    coeffsRealR = new float[fftSize][K];
    coeffsImagR = new float[fftSize][K];

    // Precompute A^T once (K x M)
    double[][] AT = new double[K][M];
    for (int k = 0; k < K; k++) {
      for (int i = 0; i < M; i++) AT[k][i] = A[i][k];
    }

    // For each frequency bin, form b (M) and compute coefficients c = ATAinv * AT * b
    // We'll do left and right, real and imag separately.
    // Build arrays b_real and b_imag for each freq from the irFreq maps.

    // Build mapping from index (i) to key in map (to get arrays)
    PVector[] keyArray = new PVector[M];
    int idx = 0;
    for (PVector k : irFreqL.keySet()) {
      keyArray[idx++] = new PVector(k.x, k.y);
    }

    // For each freq
    for (int f = 0; f < fftSize; f++) {
      // Build b vectors
      double[] bRealL = new double[M];
      double[] bImagL = new double[M];
      double[] bRealR = new double[M];
      double[] bImagR = new double[M];

      for (int i = 0; i < M; i++) {
        PVector key = keyArray[i];
        float[] specL = irFreqL.get(key);
        float[] specR = irFreqR.get(key);
        if (specL == null || specR == null) {
          bRealL[i] = 0.0;
          bImagL[i] = 0.0;
          bRealR[i] = 0.0;
          bImagR[i] = 0.0;
        } else {
          int ridx = 2 * f;
          bRealL[i] = specL[ridx];
          bImagL[i] = specL[ridx + 1];
          bRealR[i] = specR[ridx];
          bImagR[i] = specR[ridx + 1];
        }
      }

      // Compute AT * b (size K)
      double[] ATbRealL = new double[K];
      double[] ATbImagL = new double[K];
      double[] ATbRealR = new double[K];
      double[] ATbImagR = new double[K];
      for (int k = 0; k < K; k++) {
        double sRL = 0, sIL = 0, sRR = 0, sIR = 0;
        for (int i = 0; i < M; i++) {
          double a = AT[k][i];
          sRL += a * bRealL[i];
          sIL += a * bImagL[i];
          sRR += a * bRealR[i];
          sIR += a * bImagR[i];
        }
        ATbRealL[k] = sRL;
        ATbImagL[k] = sIL;
        ATbRealR[k] = sRR;
        ATbImagR[k] = sIR;
      }

      // c = ATAinv * ATb
      double[] cRealL = multiplyMatrixVector(ATAinv, ATbRealL);
      double[] cImagL = multiplyMatrixVector(ATAinv, ATbImagL);
      double[] cRealR = multiplyMatrixVector(ATAinv, ATbRealR);
      double[] cImagR = multiplyMatrixVector(ATAinv, ATbImagR);

      for (int k = 0; k < K; k++) {
        coeffsRealL[f][k] = (float) cRealL[k];
        coeffsImagL[f][k] = (float) cImagL[k];
        coeffsRealR[f][k] = (float) cRealR[k];
        coeffsImagR[f][k] = (float) cImagR[k];
      }
    }

    // finished fit
    println("SH fit completed: order=" + L + " coeffs=" + K + " fftSize=" + fftSize);
  }

  // Reconstruct complex spectrum (interleaved) for a given (az,el) in degrees
  // returns float[][] {irLFreq, irRFreq} each length = 2*fftSize
  public float[][] reconstructComplexSpectrum(float azDeg, float elDeg) {
    if (fftSize == 0) throw new IllegalStateException("fitSH must be called before reconstructComplexSpectrum");

    double[] Y = evalRealSHVector(azDeg, elDeg); // length K

    float[] specL = new float[2 * fftSize];
    float[] specR = new float[2 * fftSize];

    for (int f = 0; f < fftSize; f++) {
      double reL = 0, imL = 0, reR = 0, imR = 0;
      for (int k = 0; k < K; k++) {
        double yk = Y[k];
        reL += coeffsRealL[f][k] * yk;
        imL += coeffsImagL[f][k] * yk;
        reR += coeffsRealR[f][k] * yk;
        imR += coeffsImagR[f][k] * yk;
      }
      specL[2 * f]     = (float) reL;
      specL[2 * f + 1] = (float) imL;
      specR[2 * f]     = (float) reR;
      specR[2 * f + 1] = (float) imR;
    }

    return new float[][] { specL, specR };
  }

  // ---------------------- helpers: SH evaluation ----------------------
  // Evaluate real SH basis vector Y_k(az,el) length K (ordering: (l=0..L, m=-l..l))
  // az, el in degrees: azimuth (0..360), elevation (-90..90)
  private double[] evalRealSHVector(float azDeg, float elDeg) {
    double az = Math.toRadians(azDeg);
    double el = Math.toRadians(elDeg);
    // Spherical coordinates: theta = colatitude = pi/2 - elevation
    double theta = Math.PI / 2.0 - el;
    double phi = az;

    double x = Math.cos(theta); // cos(theta) = sin(el)
    // We'll compute associated Legendre P_lm(cos theta) using recurrence
    double[] Y = new double[K];
    int idx = 0;
    for (int l = 0; l <= L; l++) {
      for (int m = -l; m <= l; m++) {
        double val = realSH(l, m, theta, phi);
        Y[idx++] = val;
      }
    }
    return Y;
  }

  // Real spherical harmonic Y_lm (orthonormalized)
  // m >= 0 : sqrt(2)*N * P_lm(cos theta) * cos(m phi)  (for m>0 add sqrt(2) factor)
  // m == 0 : N * P_l0(cos theta)
  // m <  0 : sqrt(2)*N * P_l|m|(cos theta) * sin(|m| phi)
  private double realSH(int l, int m, double theta, double phi) {
    double x = Math.cos(theta); // cos(theta)
    int absm = Math.abs(m);
    double Plm = associatedLegendre(l, absm, x); // P_l^m(x)

    double Nlm = shNormalization(l, absm);

    if (m == 0) {
      return Nlm * Plm;
    } else if (m > 0) {
      return Math.sqrt(2.0) * Nlm * Plm * Math.cos(m * phi);
    } else { // m < 0
      return Math.sqrt(2.0) * Nlm * Plm * Math.sin(absm * phi);
    }
  }

  // Normalization constant N_lm = sqrt((2l+1)/(4pi) * (l-m)!/(l+m)!)
  private double shNormalization(int l, int m) {
    double num = (2 * l + 1) / (4 * Math.PI);
    double factRatio = factorialRatio(l - m, l + m);
    return Math.sqrt(num * factRatio);
  }

  // compute (l-m)! / (l+m)! as double
  private double factorialRatio(int a, int b) {
    // compute product of (a+1 .. b) inverse; better to compute using logs for larger factorials
    // but l <= 5 so it's safe to compute straightforwardly
    double res = 1.0;
    for (int i = a + 1; i <= b; i++) res /= i;
    return res;
  }

  // Associated Legendre polynomials P_l^m(x) (Schmidt seminormalized or standard?)
  // We'll use the standard associated Legendre via recurrence (for small l <= 5 it's fine).
  private double associatedLegendre(int l, int m, double x) {
    // Use simple recursion (stdlib small-l variant)
    // Start with P_m^m(x) = (-1)^m (2m-1)!! (1-x^2)^{m/2}
    double pmm = 1.0;
    if (m > 0) {
      double somx2 = Math.sqrt(1.0 - x * x);
      double fact = 1.0;
      pmm = 1.0;
      for (int i = 1; i <= m; i++) {
        pmm *= -fact * somx2;
        fact += 2.0;
      }
    }
    if (l == m) return pmm;
    double pmmp1 = x * (2 * m + 1) * pmm;
    if (l == m + 1) return pmmp1;
    double pll = 0.0;
    for (int ll = m + 2; ll <= l; ll++) {
      pll = ((2 * ll - 1) * x * pmmp1 - (ll + m - 1) * pmm) / (ll - m);
      pmm = pmmp1;
      pmmp1 = pll;
    }
    return pmmp1;
  }

  // ---------------------- small linear algebra helpers ----------------------
  // Invert square matrix using Gaussian elimination, returns null on failure
  private double[][] invertMatrix(double[][] a) {
    int n = a.length;
    double[][] A = new double[n][n];
    double[][] inv = new double[n][n];
    for (int i = 0; i < n; i++) {
      System.arraycopy(a[i], 0, A[i], 0, n);
      inv[i][i] = 1.0;
    }

    for (int i = 0; i < n; i++) {
      // find pivot
      int pivot = i;
      double pivAbs = Math.abs(A[i][i]);
      for (int r = i + 1; r < n; r++) {
        double cand = Math.abs(A[r][i]);
        if (cand > pivAbs) {
          pivot = r;
          pivAbs = cand;
        }
      }
      if (pivAbs < 1e-12) return null; // singular

      // swap if needed
      if (pivot != i) {
        double[] tmp = A[i];
        A[i] = A[pivot];
        A[pivot] = tmp;
        double[] tmp2 = inv[i];
        inv[i] = inv[pivot];
        inv[pivot] = tmp2;
      }

      // normalize row
      double diag = A[i][i];
      for (int c = 0; c < n; c++) {
        A[i][c] /= diag;
        inv[i][c] /= diag;
      }

      // eliminate other rows
      for (int r = 0; r < n; r++) {
        if (r == i) continue;
        double factor = A[r][i];
        if (factor == 0.0) continue;
        for (int c = 0; c < n; c++) {
          A[r][c] -= factor * A[i][c];
          inv[r][c] -= factor * inv[i][c];
        }
      }
    }
    return inv;
  }

  private double[] multiplyMatrixVector(double[][] M, double[] v) {
    int n = M.length;
    int m = v.length;
    double[] out = new double[n];
    for (int i = 0; i < n; i++) {
      double s = 0.0;
      double[] row = M[i];
      for (int j = 0; j < m; j++) s += row[j] * v[j];
      out[i] = s;
    }
    return out;
  }
}
/*
Uses: https://github.com/jaudiolibs/jnajack
 
 ABSOLUTELEY UNTESTED!!! Skeleton
 */





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
//let user define .json presets for speaker positions and channels

String speakerPresetsDir = "speaker_presets";

class Preset {

  boolean is2D = false; //should be deviced from speakers params
  JSONObject json;
  String name;
  int hash;
  ArrayList<Speaker> speakers = new ArrayList<Speaker>();

  PShape convexHull; //I am constructing the PSahpe as if it was an .obj => each face is a child of parent object and it consists of three points ie triangle
  float convexHullDia;//max distance from center to outermost vertex of the convexHull shape - used for max range of neighbour distance between boids
  PVector convexHullCentroid;

  Preset(File f) {
    this.json = loadJSONObject( f.getAbsolutePath() );

    this.name = this.json.getString("name");
    this.hash = this.name.hashCode();

    JSONObject normalized = normalizePositions(this.json);
    if (normalized!=null) {
      println("Calucated normalization on preset "+this.name);
      this.json = normalized;
      saveJSONObject(this.json, f.getAbsolutePath() ); //resave with added normalized positions
    }


    JSONArray jsonArr = this.json.getJSONArray( "speakers" );

    for (int i=0; i<jsonArr.size(); i++) {
      JSONObject speakerObject = jsonArr.getJSONObject(i);

      boolean lfe = false;
      //ignoring lfe speakers for now here
      if (!speakerObject.isNull("lfe")) {
        lfe = speakerObject.getBoolean("lfe");
        if ( lfe ) {
          println("ignoring lfe / subwoofer in the preset");
          continue;
        }
      }

      int index = speakerObject.getInt("index");
      String label = str(index);

      if (!speakerObject.isNull("label")) {
        label = speakerObject.getString("label");
      }

      PVector position = jsonArrayToPVector( speakerObject.getJSONArray("position_normalized") );
      Speaker currSpeaker = new Speaker(index, position, label, lfe );
      speakers.add(currSpeaker);
    }

    calculateConvexHull();
  }

  Preset(String name, ArrayList<Speaker> speakers) {
    this.name = name;
    this.hash = this.name.hashCode();
    this.speakers = speakers;
    calculateConvexHull();
  }

  void calculateConvexHull() {
    ConvexHull hull = new ConvexHull();
    ArrayList<PVector> points = new ArrayList<PVector>();
    for (int i=0; i<speakers.size(); i++) {
      Speaker currSpeaker = speakers.get(i);
      points.add(  new PVector(currSpeaker.position.x, currSpeaker.position.y, currSpeaker.position.z) );
    }
    this.convexHull = hull.calculateConvexHull(points);
    this.convexHullDia = hull.convexHullDia;
    this.convexHullCentroid = hull.convexHullCentroid;
    this.is2D = hull.is2D;
  }

  String toString() {
    String presetInfo = "3D";
    if (this.is2D) {
      presetInfo = "2D";
    }
    return (this.name+" ; Speakers: "+this.speakers.size()+":"+presetInfo);
  }
  //------------------------
  //if the preset contains only "coordinates" in real world units, normalize to -1/1 range
  //and save under "position_normalized"
  JSONObject normalizePositions(JSONObject obj) {

    JSONArray jsonArr = obj.getJSONArray( "speakers" );

    float[][] points = new float[jsonArr.size()][3];
    float[] maxVec = new float[3];
    float[] minVec = {Float.MAX_VALUE, Float.MAX_VALUE, Float.MAX_VALUE};
    for (int i=0; i<jsonArr.size(); i++) {

      JSONObject speakerObject = jsonArr.getJSONObject(i);

      if (!speakerObject.isNull("coordinates")) {

        PVector position = jsonArrayToPVector( speakerObject.getJSONArray("coordinates") );
        //find min and max values
        float[] pos = position.array();
        for (int m=0; m<pos.length; m++) {
          maxVec[m] = max(maxVec[m], pos[m]);
          minVec[m] = min(minVec[m], pos[m]);
        }
        points[i] = position.array(); //store to array
      } else {
        return null;
      }
    }

    float max = max(maxVec);
    float min = min(minVec);
    for (int i=0; i<jsonArr.size(); i++) { //for all speakers
      JSONObject speakerObject = jsonArr.getJSONObject(i);
      JSONArray posNormVec = new JSONArray();
      //speakerObject.setJSONObject();
      posNormVec.setFloat(0, map(  points[i][0], min, max, -1, 1) );
      posNormVec.setFloat(1, map(  points[i][1], min, max, -1, 1) );
      posNormVec.setFloat(2, map(  points[i][2], min, max, -1, 1)  );
      speakerObject.setJSONArray("position_normalized", posNormVec);
    }
    return obj;
  }


  //------------------------
  // Save this preset to JSON file
  void saveToJSON(String dirPath) {
    // Create folder if it doesn't exist
    File dir = new File(dataPath(dirPath));
    if (!dir.exists()) {
      dir.mkdirs();
    }

    JSONObject presetJSON = new JSONObject();
    presetJSON.setString("name", this.name);

    JSONArray speakersArray = new JSONArray();
    for (Speaker sp : speakers) {
      JSONObject spObj = new JSONObject();
      spObj.setInt("index", sp.index);
      
      spObj.setString("label", sp.label);
      spObj.setBoolean("lfe", sp.lfe);

      // store normalized position
      JSONArray posArr = new JSONArray();
      posArr.setFloat(0, sp.position.x);
      posArr.setFloat(1, sp.position.y);
      posArr.setFloat(2, sp.position.z);
      spObj.setJSONArray("position_normalized", posArr);

      speakersArray.setJSONObject(speakersArray.size(), spObj);
    }

    presetJSON.setJSONArray("speakers", speakersArray);

    // Determine output file path
    String safeName = this.name.replaceAll("\\s+", "_");
    
    String filePath = dirPath + File.separator + safeName + ".json";
    saveJSONObject(presetJSON, filePath);

    println("Saved preset to: " + filePath);
  }
}


//--------------------------------
//helper
class PresetGenerator {
  int numSpeakers = 4;
  int rows = 2;
  int cols = 2;
  float layoutWidth = 1.0;
  float layoutHeight = 1.0;
  String mode = "circular";

  HashMap<String, String[]> guiParams = new HashMap<String, String[]>();

  PresetGenerator() {
    guiParams.put("circular", new String[] { "speaker count" });
    guiParams.put("rectangular", new String[] { "rows", "columns", "width", "height" });
  }

  boolean setMode(String val) {
    if (guiParams.get(val) != null) {
      mode = val;
      return true;
    }
    return false;
  }

  Preset generatePreset(String name) {
    ArrayList<Speaker> speakers = new ArrayList<Speaker>();
    if (mode.equals("circular")) {
      speakers = generateCircularSpeakers(this.numSpeakers);
    } else if (mode.equals("rectangular")) {
      speakers = generateRectangularSpeakers(rows, cols, layoutWidth, layoutHeight);
    }
    return new Preset(name, speakers);
  }

  ArrayList<Speaker> generateSpeakers() {
    ArrayList<Speaker> speakers = new ArrayList<Speaker>();
    if (mode.equals("circular")) {
      speakers = generateCircularSpeakers(this.numSpeakers);
    } else if (mode.equals("rectangular")) {
      speakers = generateRectangularSpeakers(rows, cols, layoutWidth, layoutHeight);
    }
    return speakers;
  }

  void drawGui() {
    String currName = gui.text("name", "new preset");
    if (mode.equals("circular")) {
      this.numSpeakers = gui.sliderInt("speaker count", this.numSpeakers);
    } else if (mode.equals("rectangular")) {
      this.rows = gui.sliderInt("rows", this.rows);
      this.cols = gui.sliderInt("columns", this.cols);
      this.layoutWidth = gui.slider("width", this.layoutWidth);
      this.layoutHeight = gui.slider("height", this.layoutHeight);
    }

    if (gui.button("generate")) {
      Preset currPreset = this.generatePreset(currName);
      this.addToEngine( spatialEngine, currPreset );
    }
  }

  void toggleGui(boolean show) {
    String[] params = guiParams.get(mode);
    if (params ==null) {
      return;
    }
    for (int i=0; i<params.length; i++) {
      if (show) {
        gui.show( params[i] );
      } else {
        gui.hide( params[i] );
      }
    }
  }

  ArrayList<Speaker> generateCircularSpeakers(int numSpeakers) {
    ArrayList<Speaker> speakers = new ArrayList<Speaker>();
    float radius = 1.0;
    for (int i = 0; i < numSpeakers; i++) {
      float angle = TWO_PI * i / numSpeakers;
      float x = cos(angle) * radius;
      float y = sin(angle) * radius;
      float z = 0; // Flat 2D ring
      PVector pos = new PVector(x, y, z);
      speakers.add(new Speaker(i, pos, str(i), false));
    }
    return speakers;
  }

  ArrayList<Speaker> generateRectangularSpeakers(int rows, int cols, float width, float height) {
    ArrayList<Speaker> speakers = new ArrayList<Speaker>();

    float xSpacing = width / (cols - 1);
    float ySpacing = height / (rows - 1);

    int index = 0;

    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        float x = -width / 2 + c * xSpacing;
        float y = -height / 2 + r * ySpacing;
        float z = 0; // 2D plane

        PVector pos = new PVector(x, y, z);
        speakers.add(new Speaker(index, pos, str(index), false));
        index++;
      }
    }

    return speakers;
  }

  void addToEngine(SpatialAudio sa, Preset p) {
    sa.presets.add( p ); //generate default preset
    sa.presetNames.add(p.name);
    p.saveToJSON( dataPath(sa.settingsDir) );
  }
}//VBAN Vector Based Amplitude panning for multiple loud speakers




public class SpatialAudio {//implements Runnable

  String settingsDir = "speaker_presets";
  ArrayList<Preset>presets = new ArrayList<Preset>();
  ArrayList<String>presetNames = new ArrayList<String>();
  Preset preset = null;

  boolean showConvexHull = true; //show speaker formed convex hull viz

  int prevPresetHash; //check for preset change - call listener if it happens


  //list of active speakers with their position
  ArrayList<Speaker>speakers = new ArrayList<Speaker>();
  //keep track of selected triplet / pair per virtual source
  HashMap<Integer, int[]> previousSelections = new HashMap<Integer, int[]>();
  float selectionBias = 0.05f; // tune this to make selection stickier
  boolean is2D = false; //note 2D / 3D calculation

  Thread localThread;
  long startTime = 0; //thread start time

  float renderScale = 300.0; //multiply normalized vector by this number to render in pixel space

  int selectedSpeakerIndex = -1;

  final int DOT_PRODUCT = 0;
  final int EUCLIDIAN = 1;
  int mode = EUCLIDIAN;

  float powerSharpness = 2; //tuning parameter for sharpness, only applied to 3D layouts using triplets

  SpatialAudio() {
    loadPresets();
  }

  boolean loadPreset(Preset preset) {
    if (preset.speakers!=null) {
      this.preset = preset;
      this.setSpeakers(preset.speakers, preset.is2D); // Mark as 2D or 3D
      return true;
    }
    return false;
  }

  void loadPresets() {
    ArrayList<File>datafiles =  loadFilesFromDir( dataPath(settingsDir), ".json" );
    for (int i=0; i<datafiles.size(); i++) {
      try {
        Preset newPreset = new Preset(datafiles.get(i));
        this.presets.add( newPreset );
        this.presetNames.add(newPreset.name);
        println("loaded "+newPreset.toString());
      }
      catch(Exception e) {
        println("there was an error loading a preset: "+e);
        continue;
      }
    }
    if (this.presets.size()==0) {
      presetGenerator.setMode("circular");
      Preset newPreset = presetGenerator.generatePreset("default");
      this.presets.add(newPreset ); //generate default preset
      this.presetNames.add(newPreset.name);
    }
    this.loadPreset( this.presets.get(0) );
  }


  Preset getPresetByName(String name) {
    for (int i=0; i<presets.size(); i++) {
      Preset pre = presets.get(i);
      if ( pre.name.equals(name) ) { //match
        this.loadPreset(pre);
        return pre;
      }
    }
    return null;
  }

  float getRenderScale() {
    return renderScale;
  }

  //--------------------------------
  void setSpeakers(ArrayList<Speaker>_speakers, boolean _is2D) {
    this.is2D = _is2D; //check if z axis of all defined speakers is 0 -> is 2D
    sortSpeakersByChannel(_speakers);//Sort once here - necessary to guarantee channel order
    this.speakers = _speakers;
  }

  void sortSpeakersByChannel(ArrayList<Speaker> speakers) {
    Collections.sort(speakers, new Comparator<Speaker>() {
      public int compare(Speaker s1, Speaker s2) {
        return Integer.compare(s1.index, s2.index);
      }
    }
    );
  }
  //-----------------------------
  //This is where we calculate all the gains given audio source positon
  //we need to do this for each audio source so we clone actual speakers instances - you can grab the gains from Objects with channel index pairs
  ArrayList<Speaker> cloneSpeakers(ArrayList<Speaker>speakerList) {
    ArrayList<Speaker>clonedList = new ArrayList<Speaker>(speakerList.size());
    for (Speaker speak : speakerList) {
      clonedList.add(new Speaker(speak));
    }
    return clonedList;
  }
  //--------------------------
  HashMap<Integer, Float> getGains(int sourceId, PVector _v) {
    if (this.is2D) {
      return getGains2D(sourceId, _v); //find pairs
    } else {
      return getGains3D( sourceId, _v); //find triplets
    }
  }

  HashMap<Integer, Float> getGains3D(int sourceId, PVector _v) {
    PVector desiredDirection = _v.copy();
    desiredDirection.normalize();

    int[] prevIndices = previousSelections.getOrDefault(sourceId, new int[] { -1, -1, -1 });

    int[] topIndices = {-1, -1, -1};
    float[] topValues = new float[3];

    if (mode == DOT_PRODUCT) {
      Arrays.fill(topValues, Float.NEGATIVE_INFINITY);
    } else if (mode == EUCLIDIAN) {
      Arrays.fill(topValues, Float.POSITIVE_INFINITY);
    }

    for (int i = 0; i < this.speakers.size(); i++) {
      float val;
      if (mode == DOT_PRODUCT) {
        val = PVector.dot(desiredDirection, this.speakers.get(i).position);
        for (int prev : prevIndices) {
          if (i == prev) {
            val += selectionBias;
            break;
          }
        }
      } else {
        val = PVector.dist(desiredDirection, this.speakers.get(i).position);
        for (int prev : prevIndices) {
          if (i == prev) {
            val -= selectionBias;
            break;
          }
        }
      }

      for (int j = 0; j < 3; j++) {
        if ((mode == DOT_PRODUCT && val > topValues[j]) ||
          (mode == EUCLIDIAN && val < topValues[j])) {
          for (int k = 2; k > j; k--) {
            topValues[k] = topValues[k - 1];
            topIndices[k] = topIndices[k - 1];
          }
          topValues[j] = val;
          topIndices[j] = i;
          break;
        }
      }
    }

    // Save selection for this source
    previousSelections.put(sourceId, topIndices.clone());

    //float[] gains = new float[this.speakers.size()];
    float[] tripletGains = new float[3];
    float gainSum = 0;
    float epsilon = 0.00001f;

    for (int i = 0; i < 3; i++) {
      if (topIndices[i] != -1) {
        PVector speakerPos = this.speakers.get(topIndices[i]).position;
        PVector diff = PVector.sub(desiredDirection, speakerPos);
        float distance = diff.mag();
        float gain = 1.0f / pow(distance + epsilon, powerSharpness);
        tripletGains[i] = gain;
        gainSum += gain;
      }
    }

    // Build HashMap result----
    HashMap<Integer, Float> gainMap = new HashMap<>();
    for (int i = 0; i < 3; i++) {
      if (topIndices[i] != -1 && gainSum > 0) {
        //gains[topIndices[i]] = tripletGains[i] / gainSum;
        float normalizedGain = tripletGains[i] / gainSum;
        gainMap.put(topIndices[i], normalizedGain);
      }
    }

    return gainMap;
  }



  HashMap<Integer, Float> getGains2D(int sourceId, PVector _v) {
    PVector desiredDirection = PVector.div(_v.copy(), renderScale);
    float[] gains = new float[this.speakers.size()];
    // --- 2D Ring-Based Interpolation ---
    float sourceAngle = atan2(desiredDirection.y, desiredDirection.x);

    class SpeakerAngle {
      Speaker speaker;
      float angle;
      SpeakerAngle(Speaker s) {
        this.speaker = s;
        this.angle = atan2(s.position.y, s.position.x);
      }
    }

    ArrayList<SpeakerAngle> speakerAngles = new ArrayList<SpeakerAngle>();
    for (Speaker s : this.speakers) {
      speakerAngles.add(new SpeakerAngle(s));
      s.gain = 0;
    }

    Collections.sort(speakerAngles, (a, b) -> Float.compare(a.angle, b.angle));

    SpeakerAngle sA = null, sB = null;
    for (int i = 0; i < speakerAngles.size(); i++) {
      SpeakerAngle curr = speakerAngles.get(i);
      SpeakerAngle next = speakerAngles.get((i + 1) % speakerAngles.size());

      float a1 = curr.angle;
      float a2 = next.angle;
      if (a2 < a1) a2 += TWO_PI;
      float sAngle = sourceAngle;
      if (sAngle < a1) sAngle += TWO_PI;

      if (sAngle >= a1 && sAngle <= a2) {
        sA = curr;
        sB = next;
        break;
      }
    }

    if (sA != null && sB != null) {
      float totalAngle = sB.angle - sA.angle;
      if (totalAngle < 0) totalAngle += TWO_PI;

      float angleToA = sourceAngle - sA.angle;
      if (angleToA < 0) angleToA += TWO_PI;

      float angleToB = totalAngle - angleToA;

      // Cosine-tapered gain
      float gainA = sq(cos(HALF_PI * (angleToA / totalAngle)));
      float gainB = sq(cos(HALF_PI * (angleToB / totalAngle)));

      float sum = gainA + gainB;
      gainA /= sum;
      gainB /= sum;

      sA.speaker.gain = gainA;
      sB.speaker.gain = gainB;
    }

    //Build HashMap result with nonzero gains ---
    HashMap<Integer, Float> gainMap = new HashMap<>();
    for (Speaker s : this.speakers) {
      if (s.gain > 0) {
        gainMap.put(s.index, s.gain);
      }
    }
    /*
    for (int i = 0; i < this.speakers.size(); i++) {
     gains[i] = this.speakers.get(i).gain;
     }
     */
    //return gains;
    return gainMap;
  }

  //--------------------------------

  void render(PGraphics screen) {
    screen.beginDraw();
    /*
    screen.pushMatrix();
     screen.scale(this.renderScale);
     screen.shape( preset.convexHull );
     screen.popMatrix();
     */

    //screen.pushStyle();

    for (int i=0; i<speakers.size(); i++ ) {
      Speaker speaker = speakers.get(i);
      speaker.render(this.renderScale, screen);
    }
    //screen.popStyle();
    //screen.lights();


    if (this.showConvexHull) {
      screen.noLights();
      screen.pushMatrix();
      screen.scale(this.renderScale);
      
      screen.hint(DISABLE_DEPTH_MASK);
      
      screen.shape( this.preset.convexHull );
      renderConvexHullEdges(screen, this.preset.convexHull);
      
      screen.hint(ENABLE_DEPTH_MASK);
      
      screen.popMatrix();   
      screen.lights();
    }


    if ( this.preset.convexHullCentroid != null) {
      screen.pushMatrix();
      PVector centroidPos = this.preset.convexHullCentroid.copy();
      centroidPos.mult(this.renderScale);

      screen.translate( centroidPos.x, centroidPos.y, centroidPos.z );
      screen.fill(200, 200, 0);
      screen.noStroke();
      
      //screen.sphereDetail(6);
      screen.sphere(15);
      screen.popMatrix();
    }

    screen.endDraw();
  }
}

//--------------------------------
class Speaker {
  PVector position;
  PVector originalPosition;
  int index; //audio output channel
  boolean active = false;

  String label;
  boolean lfe = false;

  boolean selected = false;

  float gain = 0.0; //refer to SpeakerManager - this is assigned for each calculation of the each audio source
  float dotProduct;//again just temporal storage of calculated value - refer to SpeakerManager class

  float dia = 30;
  float deafultDia = 30;

  int[] col = {127, 127, 127};
  int[] defaultCol = {0, 0, 0};

  //boolean virtual = false;
  Speaker(int _in, PVector _pos, String label, boolean lfe) {
    this.position = _pos.copy();
    this.originalPosition =  _pos.copy();
    this.index = _in;
    this.lfe = lfe;
    this.label = label;
  }

  //constructor for cloning purposes:
  Speaker(Speaker speak) {
    this.position = speak.position;
    this.index = speak.index;
    this.lfe = speak.lfe;
    this.label = speak.label;
  }

  void render(float _scale, PGraphics screen) {
    //screen.beginDraw();
    screen.pushMatrix();
    screen.lights();
    screen.translate(position.x*_scale, position.y*_scale, position.z*_scale);
    screen.stroke(0);
    /*
    if (this.selected ) {
     println("selected "+this.index);
     screen.fill(255, 255, 0);
     } else {
     screen.fill(127);
     }
     */

    for (int i=0; i<col.length; i++) {
      if (col[i] > defaultCol[i]) {
        col[i]--;
      } else if (col[i] < defaultCol[i]) {
        col[i]++;
      }
    }

    screen.fill( max(col[0], 127), max(col[1], 127), max(col[2], 127) );

    if (this.dia > this.deafultDia) {
      this.dia = this.dia - 0.1;
    }

    screen.box(this.dia);
    screen.popMatrix();

    screen.fill(255);
    screen.stroke(255);

    //draw3DLabel(this.label, this.position, _scale, 24, 20, 0, screen);
    draw3DLabel(str(index), position, _scale, 24, 50, 0, screen); //see util
    //screen.endDraw();
  }
}
//Abstraction for audio files playback


class Track {
  String name;
  String path;
  File file; //.wav file
  //SoundFile sample;
  boolean looped = false;

  boolean isStatic = true; //enable user to set the position manually in GUI rather than being set over OSC
  boolean spatial = true; //should we calculate VBAN? (binaural flag has higher priority)

  float duration;
  float volume = 1.0; //default max volume
  boolean mono = true;
  //PVector position = new PVector(0, 0, 0);

  boolean mute = false;

  //float[] sampleBuffer;

  //float[] gains;
  //HashMap<Integer, Float> gains = new HashMap<Integer, Float>();
  int index;

  long sampleIndexOffset = 0;


  //for position visualization + readymade motion animations + handles VBAP update
  VirtualSource virtualSource;

  //---------------------------------------
  // Audio stream
  private AudioInputStream audioStream;
  private AudioFormat audioFormat;
  private long totalFrames;
  // Circular buffer
  private CircularFloatBuffer circularBuffer;
  //65536 frames * 4 bytes = 262,144 bytes ? 256 KB per track
  private int circularBufferFrames = 65536; // total frames stored in circular buffer
  // Playback control
  private volatile boolean playing = false;
  //---------------------------------------

  public Track(int _index, File _f) {
    //Track(int _index, File _f) {
    this.index = _index;
    this.file = _f;
    this.name = _f.getName().replaceFirst("[.][^.]+$", ""); //remove extension (anything behind last dot in string, using regex)
    this.path = _f.getAbsolutePath();


    this.virtualSource = new VirtualSource(this.index, spatialEngine, new PVector(0, 0, 0) );

    try {
      // Open audio stream
      audioStream = AudioSystem.getAudioInputStream(this.file);
      audioFormat = audioStream.getFormat();
      totalFrames = audioStream.getFrameLength();
      circularBuffer = new CircularFloatBuffer(circularBufferFrames);

      // Compute duration in seconds
      duration = totalFrames / audioFormat.getFrameRate();
    }
    catch (Exception e) {
      println(e);
    }
  }

  //--------------------

  void update() {
    if (!isStatic) {
      virtualSource.update();
    }
    virtualSource.render(canvas);
  }

  //----------------------------------------------------------------------

  public void setPosition(PVector v) {
    virtualSource.setPosition(v);
  }

  public PVector getPosition() {
    return virtualSource.position;
  }

  void setIndex(int _index) {
    this.index = _index;
  }

  void setGains(HashMap<Integer, Float> newGains) {
    this.virtualSource.speakerGains = newGains;
    //this.gains = newGains;
  }

  HashMap<Integer, Float> getGains() {
    return this.virtualSource.speakerGains;
  }

  float getGain(int _index) {
    return this.virtualSource.speakerGains.getOrDefault(_index, 0.0);
  }

  void setGain(int _index, float val) {
    this.virtualSource.speakerGains.put(_index, val);
  }

  // --- Playback controls ---
  public void stop() {
    playing = false;
    sampleIndexOffset = 0;
    circularBuffer.clear();
    try {
      audioStream.close();
      audioStream = AudioSystem.getAudioInputStream(new File(path));
    }
    catch (Exception e) {
      e.printStackTrace();
    }
  }

  public void play() {
    playing = true;
  }
  public void pause() {
    playing = false;
  }

  /*
  public void reset() {
   stop(); // stops playback, clears circular buffer
   // reopen audio stream
   try {
   audioStream = AudioSystem.getAudioInputStream(this.file);
   circularBuffer.clear();
   sampleIndexOffset = 0;
   // Immediately fill the buffer so first bufferSwitch has data
   while (this.circularBuffer.available() < 4096) {
   fillBufferIfNeeded();
   }
   }
   catch (Exception e) {
   e.printStackTrace();
   }
   }
   */

  public boolean isPlaying() {
    return playing;
  }

  // --- Read from circular buffer at a given sample index ---
  // Returns number of frames actually read
  public int read(float[] out, int framesRequested) throws IOException {
    if (!playing) {
      // If paused, just return zeros
      Arrays.fill(out, 0f);
      return 0;
    }

    // Fill circular buffer if needed
    fillBufferIfNeeded();

    // Read frames from circular buffer
    return circularBuffer.read(out, 0, framesRequested);
  }

  private void fillBufferIfNeeded() throws IOException {
    int framesAvailable = circularBuffer.available() / audioFormat.getChannels();
    int framesToFill = circularBufferFrames - framesAvailable;
    if (framesToFill <= 0) return;

    byte[] byteBuffer = new byte[framesToFill * audioFormat.getFrameSize()];
    int bytesRead = audioStream.read(byteBuffer, 0, byteBuffer.length);

    if (bytesRead == -1) {
      if (this.looped) {
        try {
          audioStream.close();
          audioStream = AudioSystem.getAudioInputStream(this.file);
          bytesRead = audioStream.read(byteBuffer, 0, byteBuffer.length);
        }
        catch(Exception e) {
          println(e);
        }
      } else return;
    }

    int framesRead = bytesRead / audioFormat.getFrameSize();
    float[] floatBuffer = new float[framesRead]; // mono, only 1 float per frame

    // Convert bytes to float and mix down to mono
    for (int f = 0; f < framesRead; f++) {
      float sum = 0f;
      for (int ch = 0; ch < audioFormat.getChannels(); ch++) {
        int sampleIndex = f * audioFormat.getFrameSize() + ch * (audioFormat.getSampleSizeInBits() / 8);
        int sample = 0;
        if (audioFormat.getSampleSizeInBits() == 16) {
          sample = (byteBuffer[sampleIndex + 1] << 8) | (byteBuffer[sampleIndex] & 0xff);
          sum += sample / 32768f;
        } else if (audioFormat.getSampleSizeInBits() == 8) {
          sample = byteBuffer[sampleIndex];
          sum += sample / 128f;
        } else {
          throw new IOException("Unsupported sample size");
        }
      }
      floatBuffer[f] = sum / audioFormat.getChannels(); // average to mono
    }

    // Write mono data into circular buffer
    int written = 0;
    while (written < floatBuffer.length) {
      written += circularBuffer.write(floatBuffer, written, floatBuffer.length - written);
    }
  }
}

Track getLongestTrack(ArrayList<Track>tracks) {
  float max = 0;
  Track longestTrack = null;
  for (int i=0; i<tracks.size(); i++) {
    Track currTrack = tracks.get(i);
    if ( currTrack.duration>max) {
      max = currTrack.duration;
      longestTrack = currTrack;
    }
  }
  return longestTrack;
}


//----------------------------------------------------------------------------
public class CircularFloatBuffer {
  private final float[] buffer;
  private int writePos = 0;
  private int readPos = 0;
  private int available = 0;

  public CircularFloatBuffer(int capacity) {
    buffer = new float[capacity];
  }

  // Write data into buffer
  public synchronized int write(float[] data, int offset, int length) {
    int written = 0;
    for (int i = 0; i < length; i++) {
      if (available == buffer.length) break; // buffer full
      buffer[writePos] = data[offset + i];
      writePos = (writePos + 1) % buffer.length;
      available++;
      written++;
    }
    return written;
  }

  // Read data from buffer
  public synchronized int read(float[] out, int offset, int length) {
    int read = 0;
    for (int i = 0; i < length; i++) {
      if (available == 0) break; // buffer empty
      out[offset + i] = buffer[readPos];
      readPos = (readPos + 1) % buffer.length;
      available--;
      read++;
    }
    return read;
  }

  public synchronized int available() {
    return available;
  }

  public synchronized int capacity() {
    return buffer.length;
  }

  public synchronized void clear() {
    writePos = 0;
    readPos = 0;
    available = 0;
  }
}
//just for nice visualization - draw outline around speakers


class ConvexHull {

  PShape convexHull;
  float convexHullDia;//max distance from center to outermost vertex of the convexHull shape - used for max range of neighbour distance between boids
  PVector convexHullCentroid;
  boolean is2D = false;

  ConvexHull() {
  }
  //-------------------------
  PShape calculateConvexHull(ArrayList<PVector> points) {
    boolean _posZisZero = true;
    for (int i=0; i<points.size(); i++) {

      float[] loc = points.get(i).array();
      if ( loc.length<3 ) { //if only 2 axis are defined
        this.is2D = true; //must be 2D
      } else {
        if ( points.get(i).z != 0 ) {
          _posZisZero = false; //check if all z axis are 0
        }
      }
    }

    if (_posZisZero) { //all z values are 0
      this.is2D = true;
    }

    if (this.is2D) {
      PVector[] pts2D = new PVector[points.size()];
      for (int i = 0; i < points.size(); i++) {
        pts2D[i] = new PVector((float) points.get(i).x, (float) points.get(i).y);
      }
      this.convexHull = this.calculateConvexHull2D(pts2D);
      this.convexHullCentroid = this.getShapeCentroid2D(this.convexHull);
    } else {
      this.convexHull = this.calculateConvexHull3D(points);
      this.convexHullCentroid = this.getShapeCentroid3D(this.convexHull);
      //println("calculated 3D centroid: "+this.convexHullCentroid);
    }

    this.convexHullDia = this.getShapeDia(this.convexHull);

    return this.convexHull;
  }
  //-----------------------------
  float getShapeDia(PShape s) {
    float max = 0;
    PVector centr = new PVector(0, 0, 0);

    // First, check the vertices of the shape itself
    for (int i = 0; i < s.getVertexCount(); i++) {
      PVector pos = s.getVertex(i);
      float d = pos.dist(centr);
      if (d > max) max = d;
    }

    // Then, check child shapes (if any)
    for (int c = 0; c < s.getChildCount(); c++) {
      PShape f = s.getChild(c);
      for (int i = 0; i < f.getVertexCount(); i++) {
        PVector pos = f.getVertex(i);
        float d = pos.dist(centr);
        if (d > max) max = d;
      }
    }

    return max * 2; // diameter
  }
  //---------------------------------
  PVector getShapeCentroid3D(PShape s) {
    //println("get centroid");
    PVector weightedCenteresSum = null;
    float areaSum = 0.0;
    //ArrayList<PVector>centers = new ArrayList<PVector>();
    for (int ch = 0; ch < s.getChildCount(); ch++) { //for each face
      PVector face[] = new PVector[3];
      PShape currFace = s.getChild(ch);
      for (int i = 0; i < currFace.getVertexCount(); i++) {//for each vertex inside face - assumes triangle
        if (i<3) {
          face[i] = currFace.getVertex(i);
        } else {
          println("eror - getShapeCentroid() fce expects triangle face");
        }
      }
      PVector currCenter = findCentroid(face[0], face[1], face[2]);
      float[] triSides = getTriangleSides( face[0], face[1], face[2] );
      float triArea = triangleArea( triSides[0], triSides[1], triSides[2]);
      //multiply centroid by scalar area
      PVector weightedCenter = currCenter.mult(triArea);

      if ( weightedCenteresSum == null ) {
        weightedCenteresSum = weightedCenter;
      } else {
        weightedCenteresSum.add(weightedCenter);
      }
      areaSum += triArea;
    }
    //r_c = sum(r_i * m_i) / sum(m_i)
    PVector centroid = weightedCenteresSum.div(areaSum);
    return centroid;
  }
  //-------------------------------------
  PVector getShapeCentroid2D(PShape s) {
    float signedArea = 0;
    float cx = 0;
    float cy = 0;

    // We assume 's' is a single polygon (not GROUP with children)
    int vertexCount = s.getVertexCount();
    if (vertexCount < 3) {
      println("Error: Shape has fewer than 3 vertices — cannot compute centroid.");
      return new PVector(0, 0);
    }

    for (int i = 0; i < vertexCount; i++) {
      PVector p0 = s.getVertex(i);
      PVector p1 = s.getVertex((i + 1) % vertexCount);
      float cross = p0.x * p1.y - p1.x * p0.y;
      signedArea += cross;
      cx += (p0.x + p1.x) * cross;
      cy += (p0.y + p1.y) * cross;
    }

    signedArea *= 0.5;
    cx /= (6.0 * signedArea);
    cy /= (6.0 * signedArea);

    return new PVector(cx, cy);
  }

  //-------------------------
  //Graham Scan lines algorithm naively implemented here in Java ?
  PShape calculateConvexHull2D(PVector[] points) {
    int n = points.length;
    if (n < 3) {
      return null;
    }
    Vector<PVector> hull = new Vector<PVector>();
    // Find leftmost point
    int l = 0;
    for (int i = 1; i < n; i++) if (points[i].x < points[l].x) l = i;

    int p = l, q;
    do {
      hull.add(points[p]);
      q = (p + 1) % n;
      for (int i = 0; i < n; i++) {
        if (orientation(points[p], points[i], points[q]) == 2)
          q = i;
      }
      p = q;
    } while (p != l);

    // visualize hull as shape
    PShape convexHull = createShape();
    convexHull.beginShape();
    convexHull.stroke(255, 255, 0);
    convexHull.strokeWeight(0.01); //normalized
    convexHull.fill(255, 255, 0, 50);
    convexHull.normal(0, 0, 1);
    for (PVector pt : hull) convexHull.vertex(pt.x, pt.y);
    convexHull.endShape(CLOSE);

    return convexHull;
  }
  //-------------------------
  // Orientation helper (for 2D hull)
  int orientation(PVector p, PVector q, PVector r) {
    float val = (q.y - p.y) * (r.x - q.x) - (q.x - p.x) * (r.y - q.y);
    if (val == 0) return 0;
    return (val > 0) ? 1 : 2;
  }
  //-------------------------

  //uses quickHUll library
  PShape calculateConvexHull3D(ArrayList<PVector> points) {

    QuickHull3D hull = new QuickHull3D(); //init quickhull
    //we need another 3d point format for this lib - convert PVector to Point3d
    Point3d[] p3points = new Point3d[points.size()];
    for (int i=0; i<points.size(); i++) {
      p3points[i] = new Point3d (points.get(i).x, points.get(i).y, points.get(i).z);
    }

    PShape convexHull = createShape(GROUP);

    if (hull.myCheck(p3points, p3points.length) == true) {
      hull.build(p3points);  //build hull
      hull.triangulate();  //triangulate faces
      Point3d[] vertices = hull.getVertices();  //get vertices

      int[][] faceIndices = hull.getFaces();
      //run through faces (each point on each face), and draw them
      for (int i = 0; i < faceIndices.length; i++) {
        PVector[] currFace = new PVector[3];
        for (int k = 0; k < faceIndices[i].length; k++) {
          //get points that correspond to each face
          Point3d pnt2 = vertices[faceIndices[i][k]];
          currFace[k] = new PVector( (float)pnt2.x, (float)pnt2.y, (float)pnt2.z );
          //convexHull.vertex(x, y, z);
        }
        //TRIANGLES
        PShape newFace = createShape();
        newFace.beginShape();
        //newFace.noFill();
        int randCol = color( random(0, 255), random(0, 255), random(0, 255) );
        newFace.fill( randCol, 50 );
        
        newFace.noStroke();
        //newFace.stroke( randCol );
        newFace.strokeWeight(0.01); //camera space not pixel space
        PVector normal = calculateNormal(currFace);
        newFace.normal(normal.x, normal.y, normal.z); //differs to automatic println( tri.getNormal(0) );


        for (int f=0; f<currFace.length; f++) {
          newFace.vertex( currFace[f].x, currFace[f].y, currFace[f].z);
        }



        newFace.endShape();
        convexHull.addChild(newFace);
      }
      //this.convexHullCentroid.mult( getRenderScale() );
      //println("child count: "+convexHull.getChildCount());
      return convexHull;
    }
    return null;
  }

  //-------------------------
}


boolean isInside2DPolygon(PVector v, PShape shape, float safeMarginFromEdges) {
  // ------------- 2D POLYGON CHECK -------------
  int vertexCount = shape.getVertexCount();
  boolean inside = false;
  for (int i = 0, j = vertexCount - 1; i < vertexCount; j = i++) {
    PVector vi = shape.getVertex(i).copy();
    PVector vj = shape.getVertex(j).copy();

    // Check if the point is within polygon edges (ray casting algorithm)
    if (((vi.y > v.y) != (vj.y > v.y)) &&
      (v.x < (vj.x - vi.x) * (v.y - vi.y) / (vj.y - vi.y + 0.00001) + vi.x)) {
      inside = !inside;
    }
  }
  // Optional: safe margin check — shrink polygon slightly (simple approximation)
  if (inside) {
    // Check distance to edges for safe margin
    for (int i = 0, j = vertexCount - 1; i < vertexCount; j = i++) {
      PVector vi = shape.getVertex(i).copy();
      PVector vj = shape.getVertex(j).copy();
      float distToEdge = abs((vj.y - vi.y) * v.x - (vj.x - vi.x) * v.y + vj.x * vi.y - vj.y * vi.x)
        / vi.dist(vj);
      if (distToEdge < safeMarginFromEdges) {
        return false;
      }
    }
  }
  return inside;
}


boolean isInside3DPolygon(PVector v, PShape shape, float safeMarginFromEdges) {
  //iterate over all faces - guaranteed to be triangles
  for (int f=0; f< shape.getChildCount(); f++ ) { //will not work for 2D ???
    PShape currFace = shape.getChild(f);
    PVector currNormal = currFace.getNormal(0);
    PVector currPointOnFace = currFace.getVertex(0);
    //calculate perpendicular distance from boid to infinite plane defined by face triangle and normal - signed version!
    //if it is negative it means it is outside the plane's normal direction ie outiside the convex shape!
    float currDist =  shortestDistanceToPlane(currPointOnFace, currNormal, v);
    //if it is outside...
    //if (currDist< 0 ) {
    if (currDist< safeMarginFromEdges ) { //create safe 10% margin from edges - we want the food not to apear directly on surfaces
      return false;
    }
  }
  return true;
}


//Processing does not correctly render stroke() inside the PShape face...so we have to do it ourselves
void renderConvexHullEdges(PGraphics screen, PShape convexHull) {
  if (convexHull == null) return;

  for (int i = 0; i < convexHull.getChildCount(); i++) {
    PShape face = convexHull.getChild(i);

    // Get the fill int of the face
    int faceColor = face.getFill(0); // vertex index 0, all vertices have same fill in our case

    // Set stroke to face int //screen.stroke((faceColor & 0x00FFFFFF) | 0xFF000000); //100% alpha
    screen.stroke(faceColor);
    screen.strokeWeight(0.01); // adjust pixel thickness

    // Draw edges of the triangle
    int vCount = face.getVertexCount();
    for (int j = 0; j < vCount; j++) {
      PVector a = face.getVertex(j);
      PVector b = face.getVertex((j + 1) % vCount);
      screen.line(a.x, a.y, a.z, b.x, b.y, b.z);
    }
  }
}
/*
AudioEngine is the main class that handles playback
 AudioEngine holds reference to AudioBackend class that encapsulate OS specific low level class to actually send audio to outputs
 On Windows I am using ASIO
 MacOS + Linux not implemnted yet
 */


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
/*
//Ignore - just a reference to old code specific for Windows only
// inlcudes old bugs as well

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
      sharedHRTF = new SharedHrtfContext(this.bufferSize, this::onHrtfReady); //global singleton
      //this::onHrtfReady means reference to function in this class (alternative lambda is: ctx -> onHrtfReady(ctx)

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

  void onHrtfReady(SharedHrtfContext ctx) {
    for (int p=0; p<playlists.playlists.size(); p++) {
      Playlist playlist = playlists.playlists.get(p);
      for (int i=0; i<playlist.samples.size(); i++) {
        Track currTrack = playlist.getTrack(i);
        currTrack.virtualSource.initHrtf(sharedHRTF);//set shared instance
      }
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

      if (currTrack.mute) continue;

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


*///helper to show loading progress

PFont fontMedium;
PFont fontLarge;

Loading loadingStatus;

//boolean loading = false;
//boolean initialized = false;

//----------------------
class Loading {
  String loadingStatusString = "LOADING";
  String loadingString = "";
  long loadingUpdateTime = 0;
  float stringWidth = 98;
  float dotWidth = 14; //textWidth(".")
  int ticks = 0;

  boolean loading = false;
  boolean initialized = false;

  Loading() {
    fontMedium = createFont(dataPath("JetBrainsMonoNL-Regular.ttf"), 12);
    fontLarge = createFont(dataPath("JetBrainsMonoNL-Regular.ttf"), 24);
    textFont(fontLarge);
    fill(255);

    stringWidth = textWidth(loadingStatusString);
    dotWidth = textWidth(".");
  }

  void update() {
    if (!this.initialized) {
      background(0);
      textFont(fontLarge);
      fill(255);

      if (millis()-loadingUpdateTime>500) {
        ticks++;
        loadingUpdateTime = millis();
        loadingString = loadingString+".";
      }

      text(loadingStatusString, width/2-stringWidth/2, height/2-30);
      text(loadingString, width/2-(ticks*dotWidth)/2, height/2);
    }


    if (!this.initialized && !this.loading) { // && frameCount>1
      println("Loading started");
      this.loading = true;
      cursor(CROSS);
      playlists = new Playlists();

      float fov = PI/3.0;
      float cameraZ = (height/2.0) / tan(fov/2.0);

      canvas.beginDraw();
      canvas.perspective(fov, PApplet.parseFloat(width)/PApplet.parseFloat(height), cameraZ/10.0, cameraZ*100.0);
      canvas.textFont(fontLarge);
      canvas.smooth();
      //canvas.textMode(SCREEN);
      //canvas.pixelDensity(1);
      canvas.endDraw();

      surface.setResizable(true);
      surface.setLocation(100, 100);
    }

    if ( !this.initialized && playlists.loaded ) {
      println("resources loaded");
      this.initialized = true;
      this.loading = false;
    }
  }
}//compute base pass for subwoofer (for VBAN SpatialEngine)

class BiquadFilter {
  float a0, a1, a2, b1, b2;
  float z1 = 0, z2 = 0;
  float cutoff, sampleRate;
  float volume = 1.0; // multiplier

  BiquadFilter(float cutoff, float sampleRate) {
    this.cutoff = cutoff;
    this.sampleRate = sampleRate;
    setLowpass(cutoff, sampleRate);
  }

  void setCutoff(float val) {
    this.cutoff = val;
    this.setLowpass( this.cutoff, this.sampleRate);
  }

  void setVolume(float val) {
    this.volume = val;
  }

  void setLowpass(float cutoff, float sampleRate) {
    float omega = TWO_PI * cutoff / sampleRate;
    float sn = sin(omega);
    float cs = cos(omega);
    float alpha = sn / sqrt(2.0); // Q = sqrt(1/2)
    float b0 = (1 - cs) / 2;
    float b1 = 1 - cs;
    float b2 = (1 - cs) / 2;
    float a0 = 1 + alpha;
    float a1 = -2 * cs;
    float a2 = 1 - alpha;
    this.a0 = b0 / a0;
    this.a1 = b1 / a0;
    this.a2 = b2 / a0;
    this.b1 = a1 / a0;
    this.b2 = a2 / a0;
  }

  float process(float in) {
    float out = a0 * in + a1 * z1 + a2 * z2 - b1 * z1 - b2 * z2;
    z2 = z1;
    z1 = out;
    return out * this.volume;
  }

  void reset() {
    z1 = z2 = 0;
  }
}//OPen Sound Control protocol API


OscP5 oscP5;
Osc osc = null;

class Osc {
  int oscPort = 9999;
  long lastConnectionCheck = 0;
  long lastRecieved = 0;
  boolean oscListening = false;

  Osc() {
    this.init();
  }

  void init() {
    if (oscP5!=null) {
      oscP5.stop();
    }
    oscP5 = new OscP5(context, this.oscPort ); //listen
    oscListening = oscP5.isServerRunning();
    println("server listing: "+oscP5.isServerRunning() );
    println("Osc port set to: " + this.oscPort);
  }

  void checkConnection() {
    if ( lastConnectionCheck < millis()-1000 ) {
      oscListening = oscP5.isServerRunning();
      lastConnectionCheck = millis();
      if (!oscListening) {
        this.init();//try to reinit
      }
    }
  }

  void renderIcon() {
    pushStyle();
    textAlign(RIGHT, CENTER);
    String status = "DISABLED";
    if (osc != null) {
      fill(191, 13, 13);
      if (osc.oscListening) {
        if ( millis()-this.lastRecieved>1000) {
          status = "LISTENING";
          fill(127);
        } else {
          status = "INCOMING";
          fill(13, 143, 28);
        }
      }
    }
    stroke(255);
    circle(width-50, 50, 15);
    fill(255);
    textSize(14);
    text(status, width-70, 50);

    popStyle();
  }

  void setPort(int val) {
    this.oscPort = val;
    this.init(); //reinitialize
  }
}

//PARSE OSC
void oscEvent(OscMessage m) {
  //println(m);
  if (osc==null ) { //||
    return;
  } else if ( playlists == null) {
    return;
  } else if ( playlists.playlist==null  ) {
    return;
  }

  String currAddress = null;
  try {
    currAddress = m.getAddress();
  }
  catch(Exception e) {
    println("error in OSC: "+e);
    return;
  }

  osc.lastRecieved = millis();

  //----------------------------------------------------
  if (m.getAddress().endsWith("position") ) {
    int index = m.intValue(0);
    PVector currPos = new PVector( m.floatValue(1), m.floatValue(2), m.floatValue(3) );
    Track currTrack = playlists.playlist.getTrack(index);
    if (currTrack==null) {
      return;
    }

    //println(currPos);
    currTrack.setPosition(currPos);
    //---------------------------------------------------------
  } else if (m.getAddress().endsWith("gains") ) {
    //println(m);
    String currTypetag = m.getTypetag();

    int index = m.intValue(0);
    Track currTrack = playlists.playlist.getTrack(index);
    if (currTrack==null) {
      return;
    }

    HashMap<Integer, Float> currGains = new HashMap<>();
    for (int i = 1; i < currTypetag.length(); i += 2) { //ignore track index
      int channelIndex = m.intValue(i);
      float gain = m.floatValue(i + 1);
      currGains.put(channelIndex, gain);
    }
    //println(currGains.length);
    //println( "gains: "+Arrays.toString(currGains));
    currTrack.setGains(currGains);
    //----------------------------------------------------
  } else if (m.getAddress().endsWith("play") ) {
    playlists.playlist.play();
    if (syncRecToPlay) {
      host.startRecording();
    }
    //----------------------------------------------------
  } else if (m.getAddress().endsWith("stop") ) {
    playlists.playlist.stop();
    if (syncRecToPlay) {
      host.stopRecording();
    }
  }
  //----------------------------------------------------
}
//Abstraction for managing Track s

Playlists playlists;

class Playlists implements Runnable {
  Thread localThread;
  long startTime = 0;
  boolean loaded = false;
  String[] allowedFileTypes = {".wav", ".ogg", ".mp3"}; //".aac" not working, .ogg takes long to load -it sbetter to use uncompressed .wav

  String rootFolder; //where we load the playlists from by default

  String[] playlistsNames;
  ArrayList<Playlist>playlists = new  ArrayList<Playlist>();
  Playlist playlist;
  String prevPlaylistName; //just to check if the playlist was changed
  int playlistIndex = 0;

  Playlists() {
    this.localThread = new Thread(this);
    this.startTime = millis();
    this.localThread.start();
    this.rootFolder = dataPath("samples");
  }

  void setRootFolder(String val) {
    this.rootFolder = val;
  }
  //--------------------
  //load files in separate thread
  void run() {
    this.loadPlaylists();
    this.loaded = true;
  }

  //--------------------
  //run callback when finished
  void loadPlaylists() {
    playlists.clear();//clear previous options, note we are not clearing the "playlist" yet
    File[] files = listFiles( rootFolder );
    for (int i = 0; i < files.length; i++) {
      File f = files[i];
      if ( f.isDirectory() ) {
        loadPlaylist(f);
      }
    }

    if ( this.playlists != null ) {
      if (playlists.size()>0) {
        this.playlist = playlists.get(0);
        this.playlistsNames = getPlaylistsNames();
        println(playlists.size()+" playlists loaded.");
      } else {
        playlists.add( new Playlist("No playlist found") ); //we need something to avoid null pointer / problems down the line, provide placeholder
      }
    }
  }

  void loadPlaylist(File f) {
    ArrayList<File> files = loadFilesFromDir(f.getAbsolutePath(), this.allowedFileTypes );
    if (files != null && files.size() > 0) { // only add if folder contains audio files
      playlists.add(new Playlist(f, files));
    } else {
      println("Skipping empty folder: " + f.getAbsolutePath());
    }
  }

  String[] getPlaylistsNames() {
    String[] currNames = new String[playlists.size()];
    for (int i=0; i<playlists.size(); i++) {
      currNames[i] = playlists.get(i).name;
    }
    return currNames;
  }

  Playlist getPlaylistByName(String val) {
    Playlist currPlaylist = null;
    for (int i=0; i<playlists.size(); i++) {
      currPlaylist = playlists.get(i);
      if (currPlaylist.name.equals(val)) {
        return currPlaylist;
      }
    }
    return currPlaylist;
  }
  //----------------
  void playNext(boolean loopPlaylists) {
    if ( this.playlistIndex+1 > this.playlists.size()-1) {
      println("all presets played");
      if ( loopPlaylists ) {
        this.playlistIndex = 0;
      } else {
        return; //do nothing - stops playback
      }
    } else {
      this.playlistIndex++;
    }
    this.playlist = this.playlists.get(this.playlistIndex);
    this.playlist.play();//start playback
    gui.radioSet("playlist", this.playlist.name);//set gui
  }
  //-------------------
}



class Playlist {
  //final String[] requiredFieldsTrack = {"name", "loop"};
  JSONObject json;
  String name;
  float duration;
  ArrayList<Track>samples = new ArrayList<Track>();
  long started = 0;
  //boolean looped = false;
  boolean isPlaying = false;
  boolean paused = false;

  long pauseStarted = 0;
  long pauseTime = 0;

  float pos = 0.0;

  boolean loopStems = false;

  Playlist(File f, ArrayList<File>_files) {
    this.name = f.getName();//json.getString("name");
    for (int i=0; i<_files.size(); i++) {
      Track currTrack = new Track(i, _files.get(i) );
      //currTrack.setIndex(i); //assign channel to played on
      samples.add(  currTrack );
    }

    this.duration = getLongestTrack(samples).duration; //find the longest track in playlist
    println("playlist "+this.name+" created, duration: "+this.duration+" seconds");
  }

  Playlist(String _name) {
    this.name = _name;
  }

  void setLoopStems(boolean _val) {
    this.loopStems = _val;
    for (int i=0; i<samples.size(); i++) {
      samples.get(i).looped = this.loopStems;
    }
  }

  Track getTrack(int index) {
    if (samples==null) {
      return null;
    }
    if (index<samples.size()) {
      return samples.get(index);
    } else {
      return null;
    }
  }

  Track getTrackByName(String val) {
    Track currTrack = null;
    for (int i=0; i<samples.size(); i++) {
      currTrack = samples.get(i);
      if (currTrack.name.equals(val)) {
        return currTrack;
      }
    }
    return currTrack;
  }

  void play() {
    if (isPlaying) { //debounce
      return;
    }
    //reset playhead position of current asio driver pointer
    host.resetPlayhead();

    this.isPlaying = true;

    if (!paused) {
      this.started = millis();
      println("playlist "+name+" started");
    } else {
      this.pauseTime = this.pauseTime+( millis()-this.pauseStarted );
      this.paused = false;
      println("playlist "+this.name+" unpaused");
    }

    for (Track currTrack : samples) {
      //currTrack.reset();
      //currTrack.sampleIndexOffset = host.sampleIndex;//startSample;
      currTrack.play();
    }
    /*
    for (int i=0; i<samples.size(); i++) {
     Track currTrack = this.samples.get(i);
     if ( (float)(millis()-this.started-this.pauseTime)/1000 < currTrack.duration ) {
     currTrack.play(); //it will honour looped parameter of Track class
     }
     }
     */
  }

  void stop() {
    for (int i=0; i<this.samples.size(); i++) {
      Track currTrack = this.samples.get(i);
      currTrack.stop();
    }
    this.isPlaying = false;
    this.paused = false;
    this.pos = 0.0;
    println("playlist "+name+" stoppped");
  }

  void pause() {
    if (paused) {//debounce
      return;
    }
    this.pauseStarted = millis();
    //this.elapsed = (float)abs(started-pauseStarted)/1000.0;
    this.paused = true;
    this.isPlaying = false;
    for (int i=0; i<samples.size(); i++) {
      Track currTrack = samples.get(i);
      if (currTrack.isPlaying()) {
        currTrack.pause();
      }
    }
  }

  void update() {
    if (isPlaying && !paused ) {

      this.pos =  ( millis()-this.started-this.pauseTime )/1000.0;
      if ( this.pos > this.duration ) {
        if ( playbackModeInt == 0 ) {//play once
          stop(); //stop playback, do not start another
        } else if (playbackModeInt == 1) { //play all
          stop(); //stop curret playlist
          playlists.playNext(false); //start new playlist
        } else if ( playbackModeInt == 2 ) {
          stop();
          play(); //play again
        } else if ( playbackModeInt == 3 ) {
          stop(); //stop curret playlist
          playlists.playNext(true); //start new playlist and when all playlists were played, start from first one again
        }
      }
    }//end if is playing
  }//end update fce
}//enable per channel non-blocking recording



class ChannelRecorder {
    final int channelIndex;
    final int sampleRate;
    final int bufferSize;

    private AudioFormat format;
    private File wavFile;
    private OutputStream outStream;
    private ConcurrentLinkedQueue<byte[]> queue = new ConcurrentLinkedQueue<>();

    private volatile boolean running = false;
    private Thread writerThread;

    ChannelRecorder(int channelIndex, int sampleRate, int bufferSize) {
        this.channelIndex = channelIndex;
        this.sampleRate   = sampleRate;
        this.bufferSize   = bufferSize;

        this.format = new AudioFormat(
            AudioFormat.Encoding.PCM_FLOAT,
            sampleRate,
            32,     // bits
            1,      // mono
            4,      // frame size
            sampleRate,
            false
        );
    }

    public void start(String filePath) throws Exception {
        wavFile = new File(filePath);
        outStream = new BufferedOutputStream(new FileOutputStream(wavFile));
        writeWavHeaderPlaceholder();

        running = true;

        writerThread = new Thread(() -> {
            try {
                while (running || !queue.isEmpty()) {
                    byte[] data = queue.poll();
                    if (data != null) {
                        outStream.write(data);
                    } else {
                        Thread.sleep(1);
                    }
                }
                finalizeWavFile();
            } catch (Exception e) {
                e.printStackTrace();
            }
        });

        writerThread.start();
    }

    public void addSamples(float[] samples) {
        // convert float[] ? byte[]
        byte[] data = new byte[samples.length * 4];
        int idx = 0;
        for (int i = 0; i < samples.length; i++) {
            int bits = Float.floatToIntBits(samples[i]);
            data[idx++] = (byte)(bits      );
            data[idx++] = (byte)(bits >> 8 );
            data[idx++] = (byte)(bits >> 16);
            data[idx++] = (byte)(bits >> 24);
        }
        queue.add(data);
    }

    public void stop() {
        running = false;
    }

    /* WAV HEADER FUNCTIONS */
    private void writeWavHeaderPlaceholder() throws IOException {
        // Write 44 bytes placeholder. We'll rewrite it later.
        byte[] header = new byte[44];
        outStream.write(header);
    }

    private void finalizeWavFile() throws Exception {
        outStream.flush();
        long pcmSize = wavFile.length() - 44;

        RandomAccessFile raf = new RandomAccessFile(wavFile, "rw");
        raf.seek(0);

        writeCorrectWavHeader(raf, pcmSize);
        raf.close();

        outStream.close();
    }

    private void writeCorrectWavHeader(RandomAccessFile raf, long pcmSize) throws IOException {
        int sampleRate = this.sampleRate;
        int byteRate = sampleRate * 4;
        int blockAlign = 4;

        raf.writeBytes("RIFF");
        raf.writeInt(Integer.reverseBytes((int)(pcmSize + 36))); // chunk size
        raf.writeBytes("WAVE");

        raf.writeBytes("fmt ");
        raf.writeInt(Integer.reverseBytes(16));     // subchunk1 size
        raf.writeShort(Short.reverseBytes((short)3));  // PCM_FLOAT
        raf.writeShort(Short.reverseBytes((short)1));  // mono
        raf.writeInt(Integer.reverseBytes(sampleRate));
        raf.writeInt(Integer.reverseBytes(byteRate));
        raf.writeShort(Short.reverseBytes((short)blockAlign));
        raf.writeShort(Short.reverseBytes((short)32)); // bits per sample

        raf.writeBytes("data");
        raf.writeInt(Integer.reverseBytes((int)pcmSize));
    }
}
//class for virtual audio source visualization + handles update of the gains for VBAP

class VirtualSource {
  PVector position;         // 3D position of the virtual sound source
  HashMap<Integer, Float> speakerGains  = new HashMap<Integer, Float>();  // Array of gain values per speaker ; channelId:value
  SpatialAudio engine;      // Reference to the SpatialAudio engine for access
  // Track-specific binaural state
  BinauralAudioProcessor hrtf;

  int col;
  //-----------------

  String motionMode = "none";  // Set externally or here
  String[] motionModeNames = {"circle", "noise", "none"};
  Animator animator = null;  // current animator

  CircleAnimator circleAnimator = new CircleAnimator();
  NoiseAnimator noiseAnimator = new NoiseAnimator();

  int index = 0;

  VirtualSource(int index, SpatialAudio _engine, PVector _pos) {
    this.index = index;
    this.engine = _engine;
    this.position = _pos.copy();
    this.speakerGains = new HashMap<Integer, Float>();
    this.col = color(random(255), random(255), random(255)); // assign random RGB int }

  void setMotionMode(String name) {

    if (animator != null) {
      animator.toggleGui(false); //hide previous Animator GUI
    }

    motionMode = name;
    if (motionMode.equals("circle")) {
      animator = circleAnimator;
    } else if (motionMode.equals("noise")) {
      animator = noiseAnimator;
    } else {
      animator = null; // NONE
    }

    if (animator != null) {
      animator.toggleGui(true); //show current Animator GUI
    }
  }

  void drawGui() {
    if (animator != null) {
      animator.drawGui();
    }
  }

  public void initHrtf(SharedHrtfContext shared) {
    try {
      this.hrtf = new BinauralAudioProcessor(shared);
    }
    catch(Exception e) {
      println(e);
    }
  }

  void setPosition(PVector vec) {
    //println("set position: "+vec);
    this.position.set(vec);

    if (this.hrtf!=null && host.binaural) {
      this.hrtf.setPosition( new PVector(position.x, position.z, -position.y) );//reverse PeasyCam axis order ;-)
      //this.hrtf.setPosition(vec);
    }
  }

  void updateGains() {
    speakerGains = engine.getGains(this.index, position);
  }

  void update() {
    if (animator != null) {
      this.setPosition(animator.update(position) );
      //position.set(animator.update(position));
    }

    updateGains();
  }


  void render(PGraphics pg) {
    pg.pushStyle();
    pg.pushMatrix();
    pg.lights();
    pg.translate(position.x * engine.renderScale, position.y * engine.renderScale, position.z * engine.renderScale);
    pg.fill(this.col);
    pg.noStroke();
    pg.sphere(15);
    pg.popMatrix();

    // Render speaker gain lines
    for (int i = 0; i < engine.speakers.size(); i++) {
      Speaker s = engine.speakers.get(i);
      float gain = speakerGains.getOrDefault(s.index, 0.0);
      if (gain < 0.001) continue;

      PVector sp = s.position.copy().mult(engine.renderScale);
      PVector vp = position.copy().mult(engine.renderScale);

      pg.strokeWeight(2 + gain * 8);
      pg.stroke(255, 255 * gain, 0, 180);
      pg.line(vp.x, vp.y, vp.z, sp.x, sp.y, sp.z);

      //draw gain text
      draw3DLabel(nf(gain, 1, 2), sp, 1.0, 24, 0, -30, pg);
    }
    pg.popStyle();
  }
}

//--------------------------------------------------------------------------------------
//polymorphism for motion animation presets
interface Animator {
  PVector update(PVector position);
  void drawGui();
  void toggleGui(boolean show);
  String[] getGuiParams();
}

abstract class BaseAnimator implements Animator {

  public void toggleGui(boolean show) {
    String[] guiparams = getGuiParams();
    for (int i = 0; i < guiparams.length; i++) {
      if (show) {
        gui.show(guiparams[i]);
      } else {
        gui.hide(guiparams[i]);
      }
    }
  }

  // abstract methods required by all Animators
  abstract public PVector update(PVector position);
  abstract public void drawGui();
}
//--------------------------------------------------------------------------------------
class CircleAnimator extends BaseAnimator implements Animator {

  float angle = 0;          // Angle for circular motion
  float radius = 0.8;       // Radius in normalized space (1 = unit circle)
  float speed = 0.01;       // Angular speed (radians per frame)
  // circle plane rotation (radians)
  float alpha = 0.0; // rotation around X axis
  float beta  = 0.0; // rotation around Y axis

  CircleAnimator() {
    this.angle = random(0, 360); //random offset from each other
  }

  public String[] getGuiParams() {
    return new String[] {"radius", "axis X", "axis Y", "speed"};
  }

  PVector update(PVector position) {
    angle += speed;
    position.x = cos(angle) * radius;
    position.y = sin(angle) * radius;
    position.z = height;
    angle += speed;
    // Base circle in XY plane
    float x = cos(angle) * radius;
    float y = sin(angle) * radius;
    float z = 0;
    // Rotate around X axis (alpha)
    float y1 = y * cos(alpha) - z * sin(alpha);
    float z1 = y * sin(alpha) + z * cos(alpha);
    float x1 = x;
    // Rotate around Y axis (beta)
    float x2 = x1 * cos(beta) + z1 * sin(beta);
    float z2 = -x1 * sin(beta) + z1 * cos(beta);
    float y2 = y1;
    position.set(x2, y2, z2);
    return position;
  }

  void drawGui() {
    this.radius = gui.slider("radius", this.radius, 0.0001, 2.0);
    this.alpha = radians( gui.slider("axis X", degrees(this.alpha), 0.0, 360 ) ) ;
    this.beta = radians(  gui.slider("axis Y", degrees(this.beta), 0.0, 360) );
    this.speed = radians( gui.slider("speed", degrees(this.speed), 0.0001, 90) );
  }
}
//--------------------------------------------------------------------------------------
class NoiseAnimator extends BaseAnimator implements Animator {

  PVector velocity = new PVector();
  float maxSpeed = 0.01;  // max normalized units/frame
  float noiseSpeed = 0.005;  // how fast the noise changes
  float t = 0;

  NoiseAnimator() {
  }

  public String[] getGuiParams() {
    return new String[] {"speed"};
  }

  PVector update(PVector position) {
    // Smooth organic motion based on noise-derived acceleration
    float nx = noise(t);
    float ny = noise(t + 1000);
    float nz = noise(t + 2000);

    // Convert noise values [-0.5, 0.5] as directional steering force
    PVector acceleration = new PVector(nx - 0.5, ny - 0.5, nz - 0.5);
    acceleration.mult(0.02); // tuning factor for responsiveness

    // Update velocity and limit it
    velocity.add(acceleration);
    velocity.limit(maxSpeed);

    // Move position and constrain within cube
    position.add(velocity);
    position.x = constrain(position.x, -1, 1);
    position.y = constrain(position.y, -1, 1);
    position.z = constrain(position.z, -1, 1);

    t += noiseSpeed;
    return position;
  }

  void drawGui() {
    this.noiseSpeed = gui.slider("speed", this.noiseSpeed, 0.0001, 0.5);
  }
}// declare a TuioProcessing client
TuioProcessing tuioClient;

// called when a blob is moved
void updateTuioObject (TuioObject tobj) {
  int index = tobj.getSymbolID();
  PVector currPos = new PVector( (tobj.getX()*2.0f)-1.0f, (tobj.getY()*2.0f)-1.0f, 0 ); //tobj.getAngle() not used
  Track currTrack = playlists.playlist.getTrack(index);
  if (currTrack==null) {
    return;
  }
  println(currPos);
  currTrack.setPosition(currPos);
  //---------------------------------------------------------
}
//various helper functions
//----------------------------------
void openFolder(String folderPath) {
  if (folderPath==null) {
    return;
  }
  File folder = new File(folderPath);
  if (!folder.exists()) {
    println("Folder does not exist");
    return;
  }
  // Open the folder in the system file explorer
  if (Desktop.isDesktopSupported()) {
    try {
      Desktop.getDesktop().open(folder);
    }
    catch (Exception e) {
      e.printStackTrace();
    }
  } else {
    println("Desktop not supported on this system.");
  }
}

// Folder chooser function
// Run folder chooser in a separate thread
void selectFolder(java.util.function.Consumer<File> callback) {
  new Thread(() -> {
    JFileChooser chooser = new JFileChooser();
    chooser.setFileSelectionMode(JFileChooser.DIRECTORIES_ONLY);
    int result = chooser.showOpenDialog(null);
    File selected = null;
    if (result == JFileChooser.APPROVE_OPTION) {
      selected = chooser.getSelectedFile();
    }
    final File folder = selected;
    // Run callback safely on Processing main thread
    javax.swing.SwingUtilities.invokeLater(() -> callback.accept(folder));
  }).start();
}
//-----------------------------
ArrayList<File> loadFilesFromDir(String path, String[] filterExtension) {
  ArrayList<File> foundFiles = new ArrayList<File>();
  if (!Files.exists(Paths.get(path))) {
    println("Directory does NOT exist: " + path);
    return foundFiles;
  }
  File root = new File(path);
  File[] list = root.listFiles();
  if (list == null) return foundFiles;
  for (File f : list) {
    String currPathLower = f.getAbsolutePath().toLowerCase();
    for (String ext : filterExtension) {
      if (currPathLower.endsWith(ext.toLowerCase())) {
        foundFiles.add(f);
        break; // stop checking other extensions
      }
    }
  }
  return foundFiles;
}
//-----------------------------
boolean validateJson(JSONObject json, String[] params) {
  int sumParams = 0;
  for (int i=0; i< params.length; i++) {
    if ( json.hasKey(params[i])) {
      sumParams++;
    }
  }
  //println("sumParams: "+sumParams);
  if ( sumParams == params.length) {
    return true;
  }
  return false;
}
//------------------------------
float[] jsonArrayToFloatArray(JSONArray arr) {
  float[] out = new float[arr.size()];
  for (int i=0; i<arr.size(); i++) {
    out[i] = arr.getFloat(i);
  }
  return out;
}
//-----------------------------
int[] jsonArrayToIntArray(JSONArray arr) {
  int[] out = new int[arr.size()];
  for (int i=0; i<arr.size(); i++) {
    out[i] = arr.getInt(i);
  }
  return out;
}
//------------------------------------------------------------------------------
float[] addArrays(float[] array1, float[] array2) {
  float[] sumArray = new float[Math.max(array1.length, array2.length)];
  for (int i = 0; i < sumArray.length; i++) {
    float num1 = (i < array1.length) ? array1[i] : 0;
    float num2 = (i < array2.length) ? array2[i] : 0;
    sumArray[i] = num1 + num2;
  }
  return sumArray;
}
//------------------------------------------------------------------------------
float[] addArrays(ArrayList<float[]>arr) {
  //find longest array buffer first
  int maxLength = 0;
  for (int i=0; i<arr.size(); i++) {
    if (arr.get(i).length>maxLength) {
      maxLength = arr.get(i).length;
    }
  }
  float[] sumArray = new float[maxLength];
  println("maxLength "+maxLength + "list size: "+arr.size() );
  for (int i=0; i<arr.size(); i++) {
    float[] currArr = arr.get(i);
    for (int j=0; j<currArr.length; j++) {
      sumArray[j] = sumArray[j] + currArr[j];
    }
  }
  return sumArray;
}
//------------------------------
float approxRollingAverage (float avg, float new_sample, int N) {
  avg -= avg / N;
  avg += new_sample / N;
  return avg;
}
//--------------------------------
//create looping noise array in 0-1 range
float[] getLoopedNoise(int segments) {
  float[] out = new float[segments];
  float ANGLE_PER_SEGMENT = TWO_PI / segments;
  for (int i = 0; i<segments; i++ ) {
    float p = PointForIndexNormalized(i, ANGLE_PER_SEGMENT);
    out[i] = p;
  }
  return out;
}

float PointForIndexNormalized(int i, float ANGLE_PER_SEGMENT) {
  float angle = ANGLE_PER_SEGMENT * i;
  float cosAngle = cos(angle);
  float sinAngle = sin(angle);
  float noiseValue = noise(cosAngle, sinAngle);
  return noiseValue;
}
//--------------------------------
//For SpatialAudioEngine and ConvexHull

PVector jsonArrayToPVector(JSONArray arr) {
  if (arr!=null) {
    if ( arr.size()<2 ) {
      return null;
    }
    if ( arr.size()<3 ) {
      return new PVector( arr.getFloat(0), arr.getFloat(1) );
    } else {
      return new PVector( arr.getFloat(0), arr.getFloat(1), arr.getFloat(2) );
    }
  }
  return null;
}
//--------------------------------
ArrayList<File> loadFilesFromDir( String path, String filterExtension ) {
  println(path);
  ArrayList<File>foundfiles = new ArrayList<File>();
  if (!Files.exists( Paths.get(path) )) {
    println("directory does NOT exists: "+path);
    return foundfiles;
  }
  File root = new File( path );
  File[] list = root.listFiles();
  for ( File f : list ) {
    String currpath = f.getAbsolutePath();
    if ( currpath.endsWith(filterExtension)) {
      foundfiles.add(f);
    }
  }
  //println("FOUND "+foundfiles.size());
  return foundfiles;
}
//--------------------------------
void draw3DLabel(String label, PVector position, float scale, float textSize, float offsetX, float offsetY, PGraphics screen) {
  //screen.beginDraw();
  screen.pushMatrix();
  screen.translate(position.x * scale, position.y * scale, position.z * scale);

  screen.noLights(); // Text should be unaffected by lighting
  screen.fill(255);
  screen.stroke(0);
  screen.textAlign(LEFT, CENTER);

  // Get PeasyCam rotation
  float[] rotations = cam.getRotations();
  screen.rotateX(rotations[0]);
  screen.rotateY(rotations[1]);
  screen.rotateZ(rotations[2]);

  screen.textSize(textSize);
  // Offset the label slightly so it doesn't overlap the object
  screen.text(label, offsetX, offsetY, 0);
  screen.popMatrix();
  //screen.endDraw();
}
//--------------------------------
//find centroid of triangle
PVector findCentroid(PVector A, PVector B, PVector C) {
  float x = (A.x + B.x + C.x) / 3;
  float y = (A.y + B.y + C.y) / 3;
  float z = (A.z + B.z + C.z) / 3;
  return new PVector(x, y, z);
}
//--------------------------------
float[] getTriangleSides(PVector A, PVector B, PVector C) {
  float[] out = new float[3];
  out[0] = A.dist(B);
  out[1] = B.dist(C);
  out[2] = C.dist(A);
  return out;
}
//--------------------------------
float triangleArea(float r, float s, float t) {
  // Length of sides must be positive and sum of any two sides must be smaller than third side
  if (r < 0 || s < 0 || t < 0 || (r + s <= t)|| r + t <= s || s + t <= r) {
    println("Not a valid input");
    return -1;
  }
  // Finding Semi perimeter of the triangle using formula
  float S = (r + s + t) / 2;
  // Finding the area of the triangle
  float A = (float)Math.sqrt(S * (S - r) * (S - s) * (S - t));
  return A; // return area value
}
//--------------------------------
//calculate normal for given triangle face
PVector calculateNormal(PVector vec1, PVector vec2, PVector vec3) {
  PVector edge1 = vec1.copy().sub(vec2);
  PVector edge2 = vec2.copy().sub(vec3);
  PVector crsProd = edge1.cross(edge2); // Cross product between edge1 and edge2
  PVector normal = crsProd.normalize(); // Normalization of the vector
  return normal;
}

//overloaded fce
PVector calculateNormal(PVector[] vec) { //expect three vectors representing triangle
  if ( vec.length<3) {
    return null;
  }
  PVector edge1 = vec[0].copy().sub(vec[1]);
  PVector edge2 = vec[1].copy().sub(vec[2]);
  PVector crsProd = edge1.cross(edge2); // Cross product between edge1 and edge2
  PVector normal = crsProd.normalize(); // Normalization of the vector
  return normal;
}

//--------------------------------
//find perpendicular distance from point to plane defined by point laying on the plane + plane's normal vector
float shortestDistanceToPlane(PVector pointOnPlane, PVector normal, PVector target) {
  float d = -normal.x * target.x - normal.y * target.y - normal.z * target.z;
  //use signed distance - if it negative it means it is outside the plane normal ie outside of convex shape!
  d = normal.x * pointOnPlane.x + normal.y * pointOnPlane.y + normal.z * pointOnPlane.z + d;
  float e = normal.mag();
  float out = d / e;
  //println("Perpendicular distance " + "is " + out);
  return out;
}
//-------------------------------------
public static String[] getEnumNames(Class<? extends Enum<?>> e) {
    return Arrays.stream(e.getEnumConstants()).map(Enum::name).toArray(String[]::new);
}

// --------------------- WAV loading ---------------------

// Load mono WAV file as float array normalized to [-1,1]
float[] loadMonoWav(String filename) {
  try {
    AudioInputStream ais = AudioSystem.getAudioInputStream(new File(filename));
    AudioFormat format = ais.getFormat();

    if (format.getChannels() != 1) {
      println("Mono input wav required.");
      exit();
    }
    if (format.getSampleSizeInBits() != 16) {
      println("16-bit PCM mono required.");
      exit();
    }
    byte[] bytes = ais.readAllBytes();
    int samples = bytes.length / 2;
    float[] samplesF = new float[samples];
    for (int i = 0; i < samples; i++) {
      int low = bytes[2*i] & 0xff;
      int high = bytes[2*i+1];
      int val = (high << 8) | low;
      if (val > 32767) val -= 65536;
      samplesF[i] = val / 32768.0f;
    }
    ais.close();
    println("Loaded mono input wav: " + filename + " samples: " + samples);
    return samplesF;
  }
  catch (Exception e) {
    e.printStackTrace();
    exit();
  }
  return null;
}


float[][] loadStereoWav(String filename) {
  try {
    AudioInputStream ais = AudioSystem.getAudioInputStream(new File(filename));
    AudioFormat format = ais.getFormat();

    if (format.getChannels() != 2) {
      println("Stereo wav required for HRIRs.");
      exit();
    }
    if (format.getSampleSizeInBits() != 16) {
      println("16-bit PCM stereo required.");
      exit();
    }

    byte[] bytes = ais.readAllBytes();
    int samples = bytes.length / 4; // 2 channels * 2 bytes/sample
    float[] left = new float[samples];
    float[] right = new float[samples];

    for (int i = 0; i < samples; i++) {
      int lowL = bytes[4*i] & 0xff;
      int highL = bytes[4*i + 1];
      int valL = (highL << 8) | lowL;
      if (valL > 32767) valL -= 65536;
      left[i] = valL / 32768.0f;

      int lowR = bytes[4*i + 2] & 0xff;
      int highR = bytes[4*i + 3];
      int valR = (highR << 8) | lowR;
      if (valR > 32767) valR -= 65536;
      right[i] = valR / 32768.0f;
    }
    ais.close();

    // No truncation or padding here anymore!

    return new float[][]{left, right};
  }
  catch (Exception e) {
    e.printStackTrace();
    exit();
  }
  return null;
}


// Load stereo 24-bit WAV normalized to [-1,1]

float[][] loadStereoWav24(String filename) {
  try {
    AudioInputStream ais = AudioSystem.getAudioInputStream(new File(filename));
    AudioFormat format = ais.getFormat();

    if (format.getChannels() != 2) {
      println("Stereo wav required.");
      exit();
    }
    if (format.getSampleSizeInBits() != 24) {
      println("24-bit PCM stereo required.");
      exit();
    }

    byte[] bytes = ais.readAllBytes();
    int samples = bytes.length / 6; // 2 channels * 3 bytes/sample

    float[] left = new float[samples];
    float[] right = new float[samples];

    for (int i = 0; i < samples; i++) {
      // Left channel sample (3 bytes)
      int b0L = bytes[6*i] & 0xFF;
      int b1L = bytes[6*i + 1] & 0xFF;
      int b2L = bytes[6*i + 2]; // signed byte
      int valL = (b2L << 16) | (b1L << 8) | b0L;
      if ((valL & 0x800000) != 0) valL |= 0xFF000000; // sign-extend
      left[i] = valL / 8388608.0f;

      // Right channel sample (3 bytes)
      int b0R = bytes[6*i + 3] & 0xFF;
      int b1R = bytes[6*i + 4] & 0xFF;
      int b2R = bytes[6*i + 5]; // signed byte
      int valR = (b2R << 16) | (b1R << 8) | b0R;
      if ((valR & 0x800000) != 0) valR |= 0xFF000000; // sign-extend
      right[i] = valR / 8388608.0f;
    }

    ais.close();
    //println("Loaded 24-bit stereo WAV: " + filename + " samples: " + samples);

    //println("First 5 samples left channel: " + left[0] + ", " + left[1] + ", " + left[2] + ", " + left[3] + ", " + left[4]);
    //println("First 5 samples right channel: " + right[0] + ", " + right[1] + ", " + right[2] + ", " + right[3] + ", " + right[4]);

    return new float[][]{left, right};
  }
  catch (Exception e) {
    e.printStackTrace();
    exit();
  }
  return null;
}

}

