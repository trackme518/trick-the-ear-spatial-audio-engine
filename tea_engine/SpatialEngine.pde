//VBAN Vector Based Amplitude panning for multiple loud speakers

import java.util.HashMap; // import the HashMap class

import java.util.concurrent.atomic.AtomicBoolean;
import java.util.Comparator;
import java.util.Collections;
import java.util.Arrays;


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
