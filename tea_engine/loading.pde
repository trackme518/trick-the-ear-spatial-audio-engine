//helper to show loading progress

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
      canvas.perspective(fov, float(width)/float(height), cameraZ/10.0, cameraZ*100.0);
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
}
