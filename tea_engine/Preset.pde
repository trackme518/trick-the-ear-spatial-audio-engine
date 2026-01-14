//let user define .json presets for speaker positions and channels

String speakerPresetsDir = "speaker_presets";

class Preset {

  boolean is2D = false; //should be deviced from speakers params
  JSONObject json;
  String name;
  int hash;
  ArrayList<Speaker> speakers = new ArrayList<Speaker>();
  //subset of speakers - just a helper reference with channel indeces for subwoofers, help inside AudioEngine host instance
  ArrayList<Integer> subChannels = new ArrayList<>();

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
    this.subChannels.clear();

    for (int i=0; i<jsonArr.size(); i++) {
      JSONObject speakerObject = jsonArr.getJSONObject(i);
      int index = speakerObject.getInt("index");
      String label = str(index);

      boolean lfe = false;
      //ignoring lfe speakers for now here
      if (speakerObject.hasKey("lfe")) {
        lfe = speakerObject.getBoolean("lfe");
        if ( lfe ) {
          this.subChannels.add(index);
        }
      }

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
      if (currSpeaker.lfe) {
        continue; //ignore subwoorfers when calculating convexHull
      }
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
    speakers.add(new Speaker( speakers.size(), new PVector(0.25, 0.25, 0), "subwoofer", true ) ); //add subwoofer as an example
    return new Preset(name, speakers);
  }

  /*
  ArrayList<Speaker> generateSpeakers() {
   ArrayList<Speaker> speakers = new ArrayList<Speaker>();
   if (mode.equals("circular")) {
   speakers = generateCircularSpeakers(this.numSpeakers);
   } else if (mode.equals("rectangular")) {
   speakers = generateRectangularSpeakers(rows, cols, layoutWidth, layoutHeight);
   }
   speakers.add(new Speaker( speakers.size(), new PVector(0.25,0.25,0), "subwoofer", true ) ); //add subwoofer as an example
   return speakers;
   }
   */

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
      this.addToEngine( host.spatialEngine, currPreset );
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
}
