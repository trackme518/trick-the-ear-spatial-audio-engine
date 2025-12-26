// ---------- helper for BinauralAudioProcessor (HRTF tab) - spehrical harmonics interpolation of HRIRs ----------
// import statements near top of file:
import java.util.ArrayList;
import java.util.List;
import java.util.Set;

// Put this inner class in place of your old HrirInterpolator
public class HrirInterpolatorSH {
  // SH order
  private final int L = 5;           // order
  private final int K = (L + 1) * (L + 1); // 36 coeffs for L=5

  // precomputed design matrix and inverse ATA
  // A: M x K (M = #measurements)
  private double[][] A;         // M x K (double)
  private double[][] ATAinv;    // K x K inverse of A^T A
  private int M;                // number of measurements
  private List<PVector> dirs;   // measurement directions (az,el) in degrees, length M

  // SH coefficients per frequency and ear:
  // coeffsRealLeft[freq][k], coeffsImagLeft[freq][k]
  private float[][] coeffsRealL;
  private float[][] coeffsImagL;
  private float[][] coeffsRealR;
  private float[][] coeffsImagR;

  private int fftSize = 0;

  // ---------- public API ----------
  // Fit SH coeffs from frequency-domain complex HRIR maps
  // irFreqL and irFreqR maps: keys = PVector(az,el), value = float[2*fftSize] (complex interleaved)
  // fftSize is the number of complex bins (not the length of time IR)
  public void fitSH(Map<PVector, float[]> irFreqL, Map<PVector, float[]> irFreqR, int fftSizeIn) throws Exception {
    this.fftSize = fftSizeIn;
    // Build direction list and M
    dirs = new ArrayList<>();
    for (PVector k : irFreqL.keySet()) {
      dirs.add(new PVector(k.x, k.y)); // only (az,el)
    }
    M = dirs.size();

    if (M == 0) {
      throw new IllegalArgumentException("No measurement directions found for SH fit");
    }

    // Build A matrix (M x K)
    A = new double[M][K];
    for (int i = 0; i < M; i++) {
      double[] Y = evalRealSHVector(dirs.get(i).x, dirs.get(i).y); // length K
      System.arraycopy(Y, 0, A[i], 0, K);
    }

    // Compute ATA = A^T * A (K x K)
    double[][] ATA = new double[K][K];
    for (int a = 0; a < K; a++) {
      for (int b = 0; b < K; b++) {
        double s = 0.0;
        for (int i = 0; i < M; i++) s += A[i][a] * A[i][b];
        ATA[a][b] = s;
      }
    }

    // Invert ATA (K x K)
    ATAinv = invertMatrix(ATA);
    if (ATAinv == null) throw new Exception("Failed to invert ATA matrix for SH fit");

    // Allocate coefficient arrays: fftSize x K
    coeffsRealL = new float[fftSize][K];
    coeffsImagL = new float[fftSize][K];
    coeffsRealR = new float[fftSize][K];
    coeffsImagR = new float[fftSize][K];

    // Precompute A^T once (K x M)
    double[][] AT = new double[K][M];
    for (int k = 0; k < K; k++) {
      for (int i = 0; i < M; i++) AT[k][i] = A[i][k];
    }

    // For each frequency bin, form b (M) and compute coefficients c = ATAinv * AT * b
    // We'll do left and right, real and imag separately.
    // Build arrays b_real and b_imag for each freq from the irFreq maps.

    // Build mapping from index (i) to key in map (to get arrays)
    PVector[] keyArray = new PVector[M];
    int idx = 0;
    for (PVector k : irFreqL.keySet()) {
      keyArray[idx++] = new PVector(k.x, k.y);
    }

    // For each freq
    for (int f = 0; f < fftSize; f++) {
      // Build b vectors
      double[] bRealL = new double[M];
      double[] bImagL = new double[M];
      double[] bRealR = new double[M];
      double[] bImagR = new double[M];

      for (int i = 0; i < M; i++) {
        PVector key = keyArray[i];
        float[] specL = irFreqL.get(key);
        float[] specR = irFreqR.get(key);
        if (specL == null || specR == null) {
          bRealL[i] = 0.0;
          bImagL[i] = 0.0;
          bRealR[i] = 0.0;
          bImagR[i] = 0.0;
        } else {
          int ridx = 2 * f;
          bRealL[i] = specL[ridx];
          bImagL[i] = specL[ridx + 1];
          bRealR[i] = specR[ridx];
          bImagR[i] = specR[ridx + 1];
        }
      }

      // Compute AT * b (size K)
      double[] ATbRealL = new double[K];
      double[] ATbImagL = new double[K];
      double[] ATbRealR = new double[K];
      double[] ATbImagR = new double[K];
      for (int k = 0; k < K; k++) {
        double sRL = 0, sIL = 0, sRR = 0, sIR = 0;
        for (int i = 0; i < M; i++) {
          double a = AT[k][i];
          sRL += a * bRealL[i];
          sIL += a * bImagL[i];
          sRR += a * bRealR[i];
          sIR += a * bImagR[i];
        }
        ATbRealL[k] = sRL;
        ATbImagL[k] = sIL;
        ATbRealR[k] = sRR;
        ATbImagR[k] = sIR;
      }

      // c = ATAinv * ATb
      double[] cRealL = multiplyMatrixVector(ATAinv, ATbRealL);
      double[] cImagL = multiplyMatrixVector(ATAinv, ATbImagL);
      double[] cRealR = multiplyMatrixVector(ATAinv, ATbRealR);
      double[] cImagR = multiplyMatrixVector(ATAinv, ATbImagR);

      for (int k = 0; k < K; k++) {
        coeffsRealL[f][k] = (float) cRealL[k];
        coeffsImagL[f][k] = (float) cImagL[k];
        coeffsRealR[f][k] = (float) cRealR[k];
        coeffsImagR[f][k] = (float) cImagR[k];
      }
    }

    // finished fit
    println("SH fit completed: order=" + L + " coeffs=" + K + " fftSize=" + fftSize);
  }

  // Reconstruct complex spectrum (interleaved) for a given (az,el) in degrees
  // returns float[][] {irLFreq, irRFreq} each length = 2*fftSize
  public float[][] reconstructComplexSpectrum(float azDeg, float elDeg) {
    if (fftSize == 0) throw new IllegalStateException("fitSH must be called before reconstructComplexSpectrum");

    double[] Y = evalRealSHVector(azDeg, elDeg); // length K

    float[] specL = new float[2 * fftSize];
    float[] specR = new float[2 * fftSize];

    for (int f = 0; f < fftSize; f++) {
      double reL = 0, imL = 0, reR = 0, imR = 0;
      for (int k = 0; k < K; k++) {
        double yk = Y[k];
        reL += coeffsRealL[f][k] * yk;
        imL += coeffsImagL[f][k] * yk;
        reR += coeffsRealR[f][k] * yk;
        imR += coeffsImagR[f][k] * yk;
      }
      specL[2 * f]     = (float) reL;
      specL[2 * f + 1] = (float) imL;
      specR[2 * f]     = (float) reR;
      specR[2 * f + 1] = (float) imR;
    }

    return new float[][] { specL, specR };
  }

  // ---------------------- helpers: SH evaluation ----------------------
  // Evaluate real SH basis vector Y_k(az,el) length K (ordering: (l=0..L, m=-l..l))
  // az, el in degrees: azimuth (0..360), elevation (-90..90)
  private double[] evalRealSHVector(float azDeg, float elDeg) {
    double az = Math.toRadians(azDeg);
    double el = Math.toRadians(elDeg);
    // Spherical coordinates: theta = colatitude = pi/2 - elevation
    double theta = Math.PI / 2.0 - el;
    double phi = az;

    double x = Math.cos(theta); // cos(theta) = sin(el)
    // We'll compute associated Legendre P_lm(cos theta) using recurrence
    double[] Y = new double[K];
    int idx = 0;
    for (int l = 0; l <= L; l++) {
      for (int m = -l; m <= l; m++) {
        double val = realSH(l, m, theta, phi);
        Y[idx++] = val;
      }
    }
    return Y;
  }

  // Real spherical harmonic Y_lm (orthonormalized)
  // m >= 0 : sqrt(2)*N * P_lm(cos theta) * cos(m phi)  (for m>0 add sqrt(2) factor)
  // m == 0 : N * P_l0(cos theta)
  // m <  0 : sqrt(2)*N * P_l|m|(cos theta) * sin(|m| phi)
  private double realSH(int l, int m, double theta, double phi) {
    double x = Math.cos(theta); // cos(theta)
    int absm = Math.abs(m);
    double Plm = associatedLegendre(l, absm, x); // P_l^m(x)

    double Nlm = shNormalization(l, absm);

    if (m == 0) {
      return Nlm * Plm;
    } else if (m > 0) {
      return Math.sqrt(2.0) * Nlm * Plm * Math.cos(m * phi);
    } else { // m < 0
      return Math.sqrt(2.0) * Nlm * Plm * Math.sin(absm * phi);
    }
  }

  // Normalization constant N_lm = sqrt((2l+1)/(4pi) * (l-m)!/(l+m)!)
  private double shNormalization(int l, int m) {
    double num = (2 * l + 1) / (4 * Math.PI);
    double factRatio = factorialRatio(l - m, l + m);
    return Math.sqrt(num * factRatio);
  }

  // compute (l-m)! / (l+m)! as double
  private double factorialRatio(int a, int b) {
    // compute product of (a+1 .. b) inverse; better to compute using logs for larger factorials
    // but l <= 5 so it's safe to compute straightforwardly
    double res = 1.0;
    for (int i = a + 1; i <= b; i++) res /= i;
    return res;
  }

  // Associated Legendre polynomials P_l^m(x) (Schmidt seminormalized or standard?)
  // We'll use the standard associated Legendre via recurrence (for small l <= 5 it's fine).
  private double associatedLegendre(int l, int m, double x) {
    // Use simple recursion (stdlib small-l variant)
    // Start with P_m^m(x) = (-1)^m (2m-1)!! (1-x^2)^{m/2}
    double pmm = 1.0;
    if (m > 0) {
      double somx2 = Math.sqrt(1.0 - x * x);
      double fact = 1.0;
      pmm = 1.0;
      for (int i = 1; i <= m; i++) {
        pmm *= -fact * somx2;
        fact += 2.0;
      }
    }
    if (l == m) return pmm;
    double pmmp1 = x * (2 * m + 1) * pmm;
    if (l == m + 1) return pmmp1;
    double pll = 0.0;
    for (int ll = m + 2; ll <= l; ll++) {
      pll = ((2 * ll - 1) * x * pmmp1 - (ll + m - 1) * pmm) / (ll - m);
      pmm = pmmp1;
      pmmp1 = pll;
    }
    return pmmp1;
  }

  // ---------------------- small linear algebra helpers ----------------------
  // Invert square matrix using Gaussian elimination, returns null on failure
  private double[][] invertMatrix(double[][] a) {
    int n = a.length;
    double[][] A = new double[n][n];
    double[][] inv = new double[n][n];
    for (int i = 0; i < n; i++) {
      System.arraycopy(a[i], 0, A[i], 0, n);
      inv[i][i] = 1.0;
    }

    for (int i = 0; i < n; i++) {
      // find pivot
      int pivot = i;
      double pivAbs = Math.abs(A[i][i]);
      for (int r = i + 1; r < n; r++) {
        double cand = Math.abs(A[r][i]);
        if (cand > pivAbs) {
          pivot = r;
          pivAbs = cand;
        }
      }
      if (pivAbs < 1e-12) return null; // singular

      // swap if needed
      if (pivot != i) {
        double[] tmp = A[i];
        A[i] = A[pivot];
        A[pivot] = tmp;
        double[] tmp2 = inv[i];
        inv[i] = inv[pivot];
        inv[pivot] = tmp2;
      }

      // normalize row
      double diag = A[i][i];
      for (int c = 0; c < n; c++) {
        A[i][c] /= diag;
        inv[i][c] /= diag;
      }

      // eliminate other rows
      for (int r = 0; r < n; r++) {
        if (r == i) continue;
        double factor = A[r][i];
        if (factor == 0.0) continue;
        for (int c = 0; c < n; c++) {
          A[r][c] -= factor * A[i][c];
          inv[r][c] -= factor * inv[i][c];
        }
      }
    }
    return inv;
  }

  private double[] multiplyMatrixVector(double[][] M, double[] v) {
    int n = M.length;
    int m = v.length;
    double[] out = new double[n];
    for (int i = 0; i < n; i++) {
      double s = 0.0;
      double[] row = M[i];
      for (int j = 0; j < m; j++) s += row[j] * v[j];
      out[i] = s;
    }
    return out;
  }
}
