//Abstraction for audio files playback

import javax.sound.sampled.*;
import java.io.File;
import java.io.IOException;
import java.util.HashMap;

class Track {
  String name;
  String path;
  File file; //.wav file
  //SoundFile sample;
  boolean looped = false;

  boolean isStatic = true; //enable user to set the position manually in GUI rather than being set over OSC
  boolean spatial = true; //should we calculate VBAN? (binaural flag has higher priority)

  float duration;
  float volume = 1.0; //default max volume
  boolean mono = true;
  //PVector position = new PVector(0, 0, 0);

  boolean mute = false;

  //float[] sampleBuffer;

  //float[] gains;
  //HashMap<Integer, Float> gains = new HashMap<Integer, Float>();
  int index;

  long sampleIndexOffset = 0;


  //for position visualization + readymade motion animations + handles VBAP update
  VirtualSource virtualSource;

  //---------------------------------------
  // Audio stream
  private AudioInputStream audioStream;
  private AudioFormat audioFormat;
  private long totalFrames;
  // Circular buffer
  private CircularFloatBuffer circularBuffer;
  //65536 frames * 4 bytes = 262,144 bytes ≈ 256 KB per track
  private int circularBufferFrames = 65536; // total frames stored in circular buffer
  // Playback control
  private volatile boolean playing = false;
  //---------------------------------------

  public Track(int _index, File _f) {
    //Track(int _index, File _f) {
    this.index = _index;
    this.file = _f;
    this.name = _f.getName().replaceFirst("[.][^.]+$", ""); //remove extension (anything behind last dot in string, using regex)
    this.path = _f.getAbsolutePath();


    this.virtualSource = new VirtualSource(this.index, spatialEngine, new PVector(0, 0, 0) );

    try {
      // Open audio stream
      audioStream = AudioSystem.getAudioInputStream(this.file);
      audioFormat = audioStream.getFormat();
      totalFrames = audioStream.getFrameLength();
      circularBuffer = new CircularFloatBuffer(circularBufferFrames);

      // Compute duration in seconds
      duration = totalFrames / audioFormat.getFrameRate();
    }
    catch (Exception e) {
      println(e);
    }
  }

  //--------------------

  void update() {
    if (!isStatic) {
      virtualSource.update();
    }
    virtualSource.render(canvas);
  }

  //----------------------------------------------------------------------

  public void setPosition(PVector v) {
    virtualSource.position.set(v);
  }

  public PVector getPosition() {
    return virtualSource.position;
  }

  void setIndex(int _index) {
    this.index = _index;
  }

  void setGains(HashMap<Integer, Float> newGains) {
    this.virtualSource.speakerGains = newGains;
    //this.gains = newGains;
  }

  HashMap<Integer, Float> getGains() {
    return this.virtualSource.speakerGains;
  }

  float getGain(int _index) {
    return this.virtualSource.speakerGains.getOrDefault(_index, 0.0);
  }

  void setGain(int _index, float val) {
    this.virtualSource.speakerGains.put(_index, val);
  }

  // --- Playback controls ---
  public void stop() {
    playing = false;
    sampleIndexOffset = 0;
    circularBuffer.clear();
    try {
      audioStream.close();
      audioStream = AudioSystem.getAudioInputStream(new File(path));
    }
    catch (Exception e) {
      e.printStackTrace();
    }
  }

  public void play() {
    playing = true;
  }
  public void pause() {
    playing = false;
  }

  /*
  public void reset() {
   stop(); // stops playback, clears circular buffer
   // reopen audio stream
   try {
   audioStream = AudioSystem.getAudioInputStream(this.file);
   circularBuffer.clear();
   sampleIndexOffset = 0;
   // Immediately fill the buffer so first bufferSwitch has data
   while (this.circularBuffer.available() < 4096) {
   fillBufferIfNeeded();
   }
   }
   catch (Exception e) {
   e.printStackTrace();
   }
   }
   */

  public boolean isPlaying() {
    return playing;
  }

  // --- Read from circular buffer at a given sample index ---
  // Returns number of frames actually read
  public int read(float[] out, int framesRequested) throws IOException {
    if (!playing) {
      // If paused, just return zeros
      Arrays.fill(out, 0f);
      return 0;
    }

    // Fill circular buffer if needed
    fillBufferIfNeeded();

    // Read frames from circular buffer
    return circularBuffer.read(out, 0, framesRequested);
  }

  private void fillBufferIfNeeded() throws IOException {
    int framesAvailable = circularBuffer.available() / audioFormat.getChannels();
    int framesToFill = circularBufferFrames - framesAvailable;
    if (framesToFill <= 0) return;

    byte[] byteBuffer = new byte[framesToFill * audioFormat.getFrameSize()];
    int bytesRead = audioStream.read(byteBuffer, 0, byteBuffer.length);

    if (bytesRead == -1) {
      if (this.looped) {
        try {
          audioStream.close();
          audioStream = AudioSystem.getAudioInputStream(this.file);
          bytesRead = audioStream.read(byteBuffer, 0, byteBuffer.length);
        }
        catch(Exception e) {
          println(e);
        }
      } else return;
    }

    int framesRead = bytesRead / audioFormat.getFrameSize();
    float[] floatBuffer = new float[framesRead]; // mono, only 1 float per frame

    // Convert bytes to float and mix down to mono
    for (int f = 0; f < framesRead; f++) {
      float sum = 0f;
      for (int ch = 0; ch < audioFormat.getChannels(); ch++) {
        int sampleIndex = f * audioFormat.getFrameSize() + ch * (audioFormat.getSampleSizeInBits() / 8);
        int sample = 0;
        if (audioFormat.getSampleSizeInBits() == 16) {
          sample = (byteBuffer[sampleIndex + 1] << 8) | (byteBuffer[sampleIndex] & 0xff);
          sum += sample / 32768f;
        } else if (audioFormat.getSampleSizeInBits() == 8) {
          sample = byteBuffer[sampleIndex];
          sum += sample / 128f;
        } else {
          throw new IOException("Unsupported sample size");
        }
      }
      floatBuffer[f] = sum / audioFormat.getChannels(); // average to mono
    }

    // Write mono data into circular buffer
    int written = 0;
    while (written < floatBuffer.length) {
      written += circularBuffer.write(floatBuffer, written, floatBuffer.length - written);
    }
  }
}

Track getLongestTrack(ArrayList<Track>tracks) {
  float max = 0;
  Track longestTrack = null;
  for (int i=0; i<tracks.size(); i++) {
    Track currTrack = tracks.get(i);
    if ( currTrack.duration>max) {
      max = currTrack.duration;
      longestTrack = currTrack;
    }
  }
  return longestTrack;
}


//----------------------------------------------------------------------------
public class CircularFloatBuffer {
  private final float[] buffer;
  private int writePos = 0;
  private int readPos = 0;
  private int available = 0;

  public CircularFloatBuffer(int capacity) {
    buffer = new float[capacity];
  }

  // Write data into buffer
  public synchronized int write(float[] data, int offset, int length) {
    int written = 0;
    for (int i = 0; i < length; i++) {
      if (available == buffer.length) break; // buffer full
      buffer[writePos] = data[offset + i];
      writePos = (writePos + 1) % buffer.length;
      available++;
      written++;
    }
    return written;
  }

  // Read data from buffer
  public synchronized int read(float[] out, int offset, int length) {
    int read = 0;
    for (int i = 0; i < length; i++) {
      if (available == 0) break; // buffer empty
      out[offset + i] = buffer[readPos];
      readPos = (readPos + 1) % buffer.length;
      available--;
      read++;
    }
    return read;
  }

  public synchronized int available() {
    return available;
  }

  public synchronized int capacity() {
    return buffer.length;
  }

  public synchronized void clear() {
    writePos = 0;
    readPos = 0;
    available = 0;
  }
}
