//class for virtual audio source visualization + handles update of the gains for VBAP

class VirtualSource {
  PVector position;         // 3D position of the virtual sound source
  HashMap<Integer, Float> speakerGains  = new HashMap<Integer, Float>();  // Array of gain values per speaker ; channelId:value
  SpatialAudio engine;      // Reference to the SpatialAudio engine for access
  // Track-specific binaural state
  BinauralAudioProcessor hrtf;

  color col;
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
    this.col = color(random(255), random(255), random(255)); // assign random RGB color
  }

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
    //println(currPos);
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
      position.set(animator.update(position));
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
}
