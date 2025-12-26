//compute base pass for subwoofer (for VBAN SpatialEngine)

class BiquadFilter {
  float a0, a1, a2, b1, b2;
  float z1 = 0, z2 = 0;
  float cutoff, sampleRate;
  float volume = 1.0; // multiplier

  BiquadFilter(float cutoff, float sampleRate) {
    this.cutoff = cutoff;
    this.sampleRate = sampleRate;
    setLowpass(cutoff, sampleRate);
  }

  void setCutoff(float val) {
    this.cutoff = val;
    this.setLowpass( this.cutoff, this.sampleRate);
  }

  void setVolume(float val) {
    this.volume = val;
  }

  void setLowpass(float cutoff, float sampleRate) {
    float omega = TWO_PI * cutoff / sampleRate;
    float sn = sin(omega);
    float cs = cos(omega);
    float alpha = sn / sqrt(2.0); // Q = sqrt(1/2)
    float b0 = (1 - cs) / 2;
    float b1 = 1 - cs;
    float b2 = (1 - cs) / 2;
    float a0 = 1 + alpha;
    float a1 = -2 * cs;
    float a2 = 1 - alpha;
    this.a0 = b0 / a0;
    this.a1 = b1 / a0;
    this.a2 = b2 / a0;
    this.b1 = a1 / a0;
    this.b2 = a2 / a0;
  }

  float process(float in) {
    float out = a0 * in + a1 * z1 + a2 * z2 - b1 * z1 - b2 * z2;
    z2 = z1;
    z1 = out;
    return out * this.volume;
  }

  void reset() {
    z1 = z2 = 0;
  }
}
