/*
 ©2025 Vojtech Leischner
 Creative Commons Attribution-NonCommercial-ShareAlike 4.0 International (CC BY-NC-SA 4.0).
 When using or distributing the code, give credit in the form of "Trick the Ear Audio Engine software (https://github.com/trackme518/trick-the-ear-spatial-audio-engine) by Vojtech Leischner (https://trackmeifyoucan.com)".
 
 Please refer to the license at https://creativecommons.org/licenses/by-nc-sa/4.0/.
 
 The author is not liable for any damage caused by the software.
 Usage of the software is completely at your own risk.
 For commercial licensing, please contact us.
 */

/*
TBD
 Add OSC API for playlist loading
 */

String windowTitle = "Trick the Ear - Audio Engine v1.4";

import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Set;


import java.util.concurrent.ConcurrentLinkedQueue;
ConcurrentLinkedQueue<Runnable> drawTasks = new ConcurrentLinkedQueue<>(); //safely sync into draw with gui.fces from other events like OSC

AudioEngine audioEngine;

PApplet context;

import peasy.PeasyCam;
PeasyCam cam;

import com.krab.lazy.*;
LazyGui gui;

float fps = 0; //running average

String rootFolder; //where we save config, playlists, recordings, presets, etc., by default it is data folder inside the project
//------------------------------
String[] playbackModes = {"play once", "play all", "loop one", "loop all"};
String[] generatePresetModes = {"circular", "rectangular"};
int playbackModeInt = 1; //default "play all"
boolean syncRecToPlay = false;
//---------------------

PGraphics canvas; //offscreen render texture for 3D speakers visualization

PresetGenerator presetGenerator;

int _width, _height; //keep track of sketch dimensions in case of resize event

void setup() {
  size(1920, 1080, P2D);
  pixelDensity(displayDensity());
  surface.setResizable(true);
  context = this;

  loadSettings(); //load supeglobal settings that are independant from GUI saves from data folder. see util fce

  //surface.setTitle(windowTitle);
  frameRate(500);

  canvas = createGraphics(width, height, P3D);

  presetGenerator = new PresetGenerator();
  //spatialEngine = new SpatialAudio();

  audioEngine = new AudioEngine();
  //audioEngine = new AsioaudioEngine();

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

  //safely sync into draw with gui.fces from other events like OSC
  while (!drawTasks.isEmpty()) {
    Runnable task = drawTasks.poll(); // removes head of queue
    task.run();                      // runs safely on main thread
  }

  //using file explorer picker
  if (gui.button("choose folder") ) {
    // Assign callback to the function
    selectFolder((File newDir) -> {
      if (newDir != null) {
        rootFolder = newDir.getAbsolutePath();
        playlists.setRootFolder(rootFolder);
        setRootFolder(rootFolder); //change recordings path, playlist path
        // Safe GUI update
        gui.radioSetOptions("playback/playlist", playlists.playlistsNames);
        gui.radioSet("playback/playlist", playlists.playlist.name);

        gui.radioSetOptions("Spatial Engine/preset", audioEngine.spatialEngine.presetNames);
        gui.radioSet("Spatial Engine/preset", audioEngine.spatialEngine.preset.name);


        println("Default playlist folder set to " + rootFolder);
      } else {
        println("Folder selection canceled.");
      }
    }
    );
  }

  //provide user with option to set the root folder - where we load playlist, presets, save recordings etc.
  gui.textSet("root folder", rootFolder);

  //==================Record GUI======================================
  gui.pushFolder("recorder");
  if (audioEngine.recordingEnabled) {
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
    audioEngine.startRecording();
  }
  if (gui.button("stop")) {
    if (syncRecToPlay) {
      playlists.playlist.stop();
    }
    audioEngine.stopRecording();
  }
  if (gui.button("open folder")) {
    openFolder(audioEngine.lastRecordingPath );
  }

  audioEngine.recordingChannels = gui.sliderInt("channels:", audioEngine.recordingChannels, 1, 128);
  gui.popFolder();

  //==================Output GUI======================================
  gui.pushFolder("output");
  String currDeviceName = gui.radio("device", audioEngine.deviceNames );

  if (gui.button("open")) {
    audioEngine.open(currDeviceName); //will call backend
  }
  gui.sliderSet("outputs:", audioEngine.backend.getOutputChannelCount());
  gui.toggleSet("active", audioEngine.backend.isActive() );

  if (gui.button("close")) {
    audioEngine.backend.close();
  }

  if (gui.button("restart")) {
    audioEngine.backend.resetRequest();
  }

  if (gui.button("control panel")) {
    audioEngine.backend.openControlPanel();
  }

  boolean isTestingMode = gui.toggle("test noise", false);
  audioEngine.setTestSound( isTestingMode );
  audioEngine.setTestingChannel( gui.sliderInt("channel index", 0, 0, 128 ) );

  gui.pushFolder("subwoofers");
  audioEngine.applyLowpass = gui.toggle("lowpass", audioEngine.applyLowpass);

  //int subCount = gui.sliderInt("count", 1, 1, 16);

  float currCutoff = gui.slider("cuttoff", 120, 0, 250);
  if (audioEngine.subLowpass!=null) {
    if ( audioEngine.subLowpass.cutoff !=  currCutoff) {
      audioEngine.subLowpass.setCutoff(currCutoff);
      println("set lowpass cutoff at "+currCutoff);
    }
  }

  float bassVolume = gui.slider("bass volume", 0.99, 0.1, 5.0);
  if (audioEngine.subLowpass!=null) {
    audioEngine.subLowpass.setVolume( bassVolume );
  }

  for (int i=0; i<16; i++) {
    if ( audioEngine.spatialEngine.preset.subChannels.size()<=i ) {
      gui.hide("sub_"+i);
      break;
    } else {
      gui.show("sub_"+i);
      gui.sliderIntSet("sub_"+i+"/channel", audioEngine.spatialEngine.preset.subChannels.get(i) );
    }
  }
  gui.popFolder(); //end subwoofers
  gui.popFolder(); //end output
  //==================Playback GUI======================================

  //select playlist
  //String currPlaylist = gui.radio("playlist", new String[]{"square", "circle", "triangle"}, "square");
  String currPlaylist = gui.radio("playback/playlist", playlists.playlistsNames, playlists.playlist.name);
  if ( !currPlaylist.equals(playlists.prevPlaylistName) ) {
    playlists.setNewPlaylist(currPlaylist); //see Playlist class - it hides previous Tracks in GUI as well and set other GUI options
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
  audioEngine.setVolume(currVolume);

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

  if (gui.button("scan folder") ) {
    playlists.loadPlaylists();
    gui.radioSetOptions("playback/playlist", playlists.playlistsNames);
    gui.radioSet("playback/playlist", playlists.playlist.name);
  }


  gui.popFolder();

  //==================OSC GUI======================================
  gui.pushFolder("OSC");
  int _currOscPort = int( gui.slider("listen port", osc.oscPort) );
  if ( _currOscPort != osc.oscPort) {
    println("set osc port");
    osc.setPort( _currOscPort );
  }
  gui.popFolder();

  //==================Tracks GUI======================================

  //enable user control when switched to manual - good for debugging
  //!warning - subwoofer channel is NOT affected as it gets calculated directly in audioEngine...maybe i can fix this later
  gui.pushFolder("Tracks" );
  for (int t=0; t< playlists.playlist.samples.size(); t++) {
    Track track = playlists.playlist.samples.get(t);

    gui.show(track.name);
    //if ( track.gains !=null) {
    gui.pushFolder(track.name);

    track.virtualSource.isManual = gui.toggle("manual", track.virtualSource.isManual); //enable user to set individual gains for each channel by hand
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
      if (i<audioEngine.outputBuffers.size()) {
        //for (int i=0; i< audioEngine.activeChannels.size(); i++) {
        gui.show(guiPath);
        if (track.virtualSource.isManual) {
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
  String selectedPresetName = gui.radio("preset", audioEngine.spatialEngine.presetNames, audioEngine.spatialEngine.preset.name );
  //if (!gui.isMouseOutsideGui() ) {//only when hovering over GUI - it collided with OSC API
  if ( !selectedPresetName.equals(audioEngine.spatialEngine.preset.name) ) { //on change hack
    audioEngine.spatialEngine.getPresetByName( selectedPresetName ); //use selected preset
    //flock1.set2D(spatialEngine.preset.is2D);
  }

  audioEngine.spatialEngine.showConvexHull = gui.toggle("show hull", audioEngine.spatialEngine.showConvexHull);
  audioEngine.spatialEngine.powerSharpness = gui.slider("sharpness", audioEngine.spatialEngine.powerSharpness, 1, 5);
  audioEngine.spatialEngine.selectionBias = gui.slider("stickiness", audioEngine.spatialEngine.selectionBias, 0.0f, 0.5);

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
    audioEngine.spatialEngine.mode = audioEngine.spatialEngine.DOT_PRODUCT;
  } else {
    audioEngine.spatialEngine.mode = audioEngine.spatialEngine.EUCLIDIAN;
  }

  audioEngine.binaural = gui.toggle("binaural/enable", audioEngine.binaural);
  audioEngine.binauralChannels[0] = gui.sliderInt("binaural/left channel", audioEngine.binauralChannels[0]);
  audioEngine.binauralChannels[1] = gui.sliderInt("binaural/right channel", audioEngine.binauralChannels[1]);

  gui.popFolder();

  //==================RENDER DRAW LOOP ======================================

  canvas.beginDraw();
  canvas.clear();
  for (Track t : playlists.playlist.samples) {
    t.update(); //updates virtual audio source internally + render visualization
  }
  canvas.endDraw();

  audioEngine.spatialEngine.render(canvas); //it will intrenally check for preset change as well
  cam.getState().apply(canvas);

  image(canvas, 0, 0);

  playlists.playlist.update();
  renderTimeline();

  //----------------------------------------
  fps = approxRollingAverage(fps, frameRate, 30);
  surface.setTitle(windowTitle+" fps: "+int(fps) );
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
  audioEngine.backend.close();
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
