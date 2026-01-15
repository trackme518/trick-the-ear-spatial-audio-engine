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
    this.loadPlaylists(); //load playlists at new dir
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
}
