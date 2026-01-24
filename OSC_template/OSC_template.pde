import oscP5.*;
import netP5.*;

NetAddress receiver;

// -------------------- Button definitions --------------------
class Button {
  String label;
  float x, y, w, h;
  color fg;
  Runnable action;
  
  // fade animation
  float alpha = 100;       // current alpha
  float targetAlpha = 100; // target alpha
  float fadeSpeed = 255 / 0.5 / frameRate; // per-frame fade for 0.5 sec
  boolean fading = false;
  
  Button(String label, float x, float y, float w, float h, Runnable action) {
    this.label = label;
    this.x = x;
    this.y = y;
    this.w = w;
    this.h = h;
    this.action = action;
    this.fg = color(255);
  }
  
  void display() {
    // smooth fade towards targetAlpha
    if (fading) {
      if (alpha < targetAlpha) {
        alpha += fadeSpeed;
        if (alpha > targetAlpha) alpha = targetAlpha;
      } else if (alpha > targetAlpha) {
        alpha -= fadeSpeed;
        if (alpha < targetAlpha) alpha = targetAlpha;
      }
      if (alpha == targetAlpha) fading = false;
    }
    
    fill(100, alpha);
    rect(x, y, w, h, 5);
    fill(fg);
    textAlign(CENTER, CENTER);
    text(label, x + w/2, y + h/2);
  }
  
  boolean isMouseOver() {
    return mouseX >= x && mouseX <= x + w && mouseY >= y && mouseY <= y + h;
  }
  
  void click() {
    if (action != null) action.run();
    // start fade animation
    targetAlpha = 255; // fade in
    fading = true;
    // schedule fade out after 0.5 sec
    final Button self = this;
    new Thread(() -> {
      try { Thread.sleep(500); } catch(Exception e) {}
      self.targetAlpha = 100; // fade out
      self.fading = true;
    }).start();
  }
}

// -------------------- Global --------------------
ArrayList<Button> buttons = new ArrayList<Button>();

void setup() {
  size(400, 400);
  receiver = new NetAddress("127.0.0.1", 9999);
  textSize(14);

  // -------------------- Create buttons --------------------
  buttons.add(new Button("Load & Play Playlist", 20, 20, 180, 30, () -> {
    //load and immedietely play a playlist at given absolute path of the directory
    OscP5.flush(receiver, "/loadPlayPlaylist", "C:\\Users\\vojo\\Downloads\\test");
  }));
  
  buttons.add(new Button("Select Playlist", 220, 20, 150, 30, () -> {
    //select playlist by name (folder name by default)
    OscP5.flush(receiver, "/setPlaylist", "composter_short");
  }));
  
  buttons.add(new Button("Load Playlist", 20, 70, 180, 30, () -> {
    //load playlist at given directory absolute path
    OscP5.flush(receiver, "/loadPlaylist", "C:\\Users\\vojo\\Downloads\\test");
  }));
  
  buttons.add(new Button("Play", 220, 70, 70, 30, () -> {
    OscP5.flush(receiver, "/play", true);
    println("play");
  }));
  
  buttons.add(new Button("Stop", 300, 70, 70, 30, () -> {
    OscP5.flush(receiver, "/stop", true);
  }));
  
  buttons.add(new Button("Set Gains", 20, 120, 180, 30, () -> {
    //set Track at index (int) 0  gains output channels manually
    OscP5.flush(receiver, "/gains", 0, 0.85f, 0.5f, 0.3f, 0.2f, 0.1f);
  }));
  
  buttons.add(new Button("Set Position", 220, 120, 150, 30, () -> {
    //set Track at index (int) 0  to PVector position - x,y,z (float)
    OscP5.flush(receiver, "/position", 0, random(0,1), random(0,1), random(0,1) );
  }));
}

void draw() {
  background(50);
  
  // draw all buttons
  for (Button b : buttons) {
    b.display();
  }
}

// -------------------- Mouse click handling --------------------
void mousePressed() {
  for (Button b : buttons) {
    if (b.isMouseOver()) {
      b.click();
    }
  }
}
