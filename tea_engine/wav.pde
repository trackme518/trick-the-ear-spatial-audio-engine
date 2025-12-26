import javax.sound.sampled.*;

// --------------------- WAV loading ---------------------

// Load mono WAV file as float array normalized to [-1,1]
float[] loadMonoWav(String filename) {
  try {
    AudioInputStream ais = AudioSystem.getAudioInputStream(new File(filename));
    AudioFormat format = ais.getFormat();

    if (format.getChannels() != 1) {
      println("Mono input wav required.");
      exit();
    }
    if (format.getSampleSizeInBits() != 16) {
      println("16-bit PCM mono required.");
      exit();
    }
    byte[] bytes = ais.readAllBytes();
    int samples = bytes.length / 2;
    float[] samplesF = new float[samples];
    for (int i = 0; i < samples; i++) {
      int low = bytes[2*i] & 0xff;
      int high = bytes[2*i+1];
      int val = (high << 8) | low;
      if (val > 32767) val -= 65536;
      samplesF[i] = val / 32768.0f;
    }
    ais.close();
    println("Loaded mono input wav: " + filename + " samples: " + samples);
    return samplesF;
  }
  catch (Exception e) {
    e.printStackTrace();
    exit();
  }
  return null;
}


float[][] loadStereoWav(String filename) {
  try {
    AudioInputStream ais = AudioSystem.getAudioInputStream(new File(filename));
    AudioFormat format = ais.getFormat();

    if (format.getChannels() != 2) {
      println("Stereo wav required for HRIRs.");
      exit();
    }
    if (format.getSampleSizeInBits() != 16) {
      println("16-bit PCM stereo required.");
      exit();
    }

    byte[] bytes = ais.readAllBytes();
    int samples = bytes.length / 4; // 2 channels * 2 bytes/sample
    float[] left = new float[samples];
    float[] right = new float[samples];

    for (int i = 0; i < samples; i++) {
      int lowL = bytes[4*i] & 0xff;
      int highL = bytes[4*i + 1];
      int valL = (highL << 8) | lowL;
      if (valL > 32767) valL -= 65536;
      left[i] = valL / 32768.0f;

      int lowR = bytes[4*i + 2] & 0xff;
      int highR = bytes[4*i + 3];
      int valR = (highR << 8) | lowR;
      if (valR > 32767) valR -= 65536;
      right[i] = valR / 32768.0f;
    }
    ais.close();

    // No truncation or padding here anymore!

    return new float[][]{left, right};
  }
  catch (Exception e) {
    e.printStackTrace();
    exit();
  }
  return null;
}


// Load stereo 24-bit WAV normalized to [-1,1]

float[][] loadStereoWav24(String filename) {
  try {
    AudioInputStream ais = AudioSystem.getAudioInputStream(new File(filename));
    AudioFormat format = ais.getFormat();

    if (format.getChannels() != 2) {
      println("Stereo wav required.");
      exit();
    }
    if (format.getSampleSizeInBits() != 24) {
      println("24-bit PCM stereo required.");
      exit();
    }

    byte[] bytes = ais.readAllBytes();
    int samples = bytes.length / 6; // 2 channels * 3 bytes/sample

    float[] left = new float[samples];
    float[] right = new float[samples];

    for (int i = 0; i < samples; i++) {
      // Left channel sample (3 bytes)
      int b0L = bytes[6*i] & 0xFF;
      int b1L = bytes[6*i + 1] & 0xFF;
      int b2L = bytes[6*i + 2]; // signed byte
      int valL = (b2L << 16) | (b1L << 8) | b0L;
      if ((valL & 0x800000) != 0) valL |= 0xFF000000; // sign-extend
      left[i] = valL / 8388608.0f;

      // Right channel sample (3 bytes)
      int b0R = bytes[6*i + 3] & 0xFF;
      int b1R = bytes[6*i + 4] & 0xFF;
      int b2R = bytes[6*i + 5]; // signed byte
      int valR = (b2R << 16) | (b1R << 8) | b0R;
      if ((valR & 0x800000) != 0) valR |= 0xFF000000; // sign-extend
      right[i] = valR / 8388608.0f;
    }

    ais.close();
    //println("Loaded 24-bit stereo WAV: " + filename + " samples: " + samples);

    //println("First 5 samples left channel: " + left[0] + ", " + left[1] + ", " + left[2] + ", " + left[3] + ", " + left[4]);
    //println("First 5 samples right channel: " + right[0] + ", " + right[1] + ", " + right[2] + ", " + right[3] + ", " + right[4]);

    return new float[][]{left, right};
  }
  catch (Exception e) {
    e.printStackTrace();
    exit();
  }
  return null;
}
