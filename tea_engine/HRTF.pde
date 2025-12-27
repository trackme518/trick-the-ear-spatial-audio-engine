// HeadRelated Transfer Function - create stereo for monitoring spatial audio with headphones
//completely different to VBAN
// -----------------------------
import java.io.File;
import java.nio.file.Paths;
import java.util.*;
import io.jhdf.HdfFile;
import io.jhdf.api.Dataset;

import java.util.List;
import org.jtransforms.fft.FloatFFT_1D;

import java.util.function.Consumer;

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
