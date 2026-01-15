//various helper functions
import javax.swing.JFileChooser;
import java.io.File;
import java.nio.file.Files;
import java.nio.file.Paths;
import java.util.Arrays;
import java.awt.Desktop;
//--------------------------------

void setRootFolder(String pathToDir) {
  if (host==null) {
    println("host null");
  }
  playlists.setRootFolder(pathToDir);
  host.setRecordingPath(pathToDir);
  host.spatialEngine.loadPresets();
  saveSettings();
}

//load global settings
void loadSettings() {
  File globalConfig = new File( dataPath("config.json") );
  if (globalConfig.exists()) {
    try {
      JSONObject globalSetting = loadJSONObject( globalConfig );
      if (globalSetting.hasKey("rootFolder")) {
        rootFolder = globalSetting.getString("rootFolder");
      }
    }
    catch(Exception e) {
      println(e);
    }
  } else {
    rootFolder = dataPath("");
    saveSettings();
  }
}

void saveSettings() {
  JSONObject globalSetting = new JSONObject();
  globalSetting.setString("rootFolder", rootFolder);
  saveJSONObject(globalSetting, dataPath("config.json") );
}


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
  }
  ).start();
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
