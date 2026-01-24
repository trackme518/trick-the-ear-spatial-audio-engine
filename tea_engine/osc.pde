//OPen Sound Control protocol API

import oscP5.*;
import netP5.*;
import java.net.InetAddress;

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

  drawTasks.add(() -> {
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
      
      gui.plotSet("Tracks/"+currTrack.name+"/position", currPos);
      gui.radioSet("Tracks/"+currTrack.name+"/animate", "none");
      gui.toggleSet("Tracks/"+currTrack.name+"/manual", false);
      gui.toggleSet("Tracks/"+currTrack.name+"/spatial", true);
      gui.toggleSet("Tracks/"+currTrack.name+"/static", true);
      
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
      
      gui.radioSet("Tracks/"+currTrack.name+"/animate", "none");
      gui.toggleSet("Tracks/"+currTrack.name+"/spatial", false);
      gui.toggleSet("Tracks/"+currTrack.name+"/static", true);
      gui.toggleSet("Tracks/"+currTrack.name+"/manual", true);

      
      //----------------------------------------------------
    } else if (m.getAddress().endsWith("play") ) {
      playlists.playlist.play();
      if (syncRecToPlay) {
        audioEngine.startRecording();
      }
      //----------------------------------------------------
    } else if (m.getAddress().endsWith("stop") ) {
      playlists.playlist.stop();
      if (syncRecToPlay) {
        audioEngine.stopRecording();
      }
      //----------------------------------------------------
    } else if (m.getAddress().endsWith("setPlaylist") && m.getTypetag().equals("s") ) {
      String val = m.stringValue(0);
      println("recieved command for changing playlist to "+val);
      playlists.setNewPlaylist(  val ); //set new playlist by name
      //----------------------------------------------------
    } else if (m.getAddress().endsWith("loadPlaylist") && m.getTypetag().equals("s") ) {
      String val = m.stringValue(0);
      println("recieved command to load new playlist at dir path "+val);
      Playlist newPlaylist = playlists.loadPlaylist( new File(val) ); //set new playlist by name
      if (newPlaylist==null) {
        println("loading new playlist failed");
      }
      //----------------------------------------------------
    } else if (m.getAddress().endsWith("loadPlayPlaylist") && m.getTypetag().equals("s") ) {
      String dir = m.stringValue(0);
      println("recieved command to load & play new playlist at dir path "+dir);
      Playlist newPlaylist = playlists.loadPlaylist(new File(dir));
      if (newPlaylist != null) {
        playlists.setNewPlaylist(newPlaylist, true);
      } else {
        println("Failed to load playlist at " + dir);
      }
    }
    //---------------------------------------------------------
  }
  );//end add to draw tasks
}
