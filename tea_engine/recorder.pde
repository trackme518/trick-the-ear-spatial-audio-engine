//enable per channel non-blocking recording


import javax.sound.sampled.AudioFormat;
import java.io.File;
import java.io.FileOutputStream;
import java.io.BufferedOutputStream;
import java.io.OutputStream;
import java.io.RandomAccessFile;
import java.io.IOException;
import java.util.concurrent.ConcurrentLinkedQueue;

class ChannelRecorder {
    final int channelIndex;
    final int sampleRate;
    final int bufferSize;

    private AudioFormat format;
    private File wavFile;
    private OutputStream outStream;
    private ConcurrentLinkedQueue<byte[]> queue = new ConcurrentLinkedQueue<>();

    private volatile boolean running = false;
    private Thread writerThread;

    ChannelRecorder(int channelIndex, int sampleRate, int bufferSize) {
        this.channelIndex = channelIndex;
        this.sampleRate   = sampleRate;
        this.bufferSize   = bufferSize;

        this.format = new AudioFormat(
            AudioFormat.Encoding.PCM_FLOAT,
            sampleRate,
            32,     // bits
            1,      // mono
            4,      // frame size
            sampleRate,
            false
        );
    }

    public void start(String filePath) throws Exception {
        wavFile = new File(filePath);
        outStream = new BufferedOutputStream(new FileOutputStream(wavFile));
        writeWavHeaderPlaceholder();

        running = true;

        writerThread = new Thread(() -> {
            try {
                while (running || !queue.isEmpty()) {
                    byte[] data = queue.poll();
                    if (data != null) {
                        outStream.write(data);
                    } else {
                        Thread.sleep(1);
                    }
                }
                finalizeWavFile();
            } catch (Exception e) {
                e.printStackTrace();
            }
        });

        writerThread.start();
    }

    public void addSamples(float[] samples) {
        // convert float[] → byte[]
        byte[] data = new byte[samples.length * 4];
        int idx = 0;
        for (int i = 0; i < samples.length; i++) {
            int bits = Float.floatToIntBits(samples[i]);
            data[idx++] = (byte)(bits      );
            data[idx++] = (byte)(bits >> 8 );
            data[idx++] = (byte)(bits >> 16);
            data[idx++] = (byte)(bits >> 24);
        }
        queue.add(data);
    }

    public void stop() {
        running = false;
    }

    /* WAV HEADER FUNCTIONS */
    private void writeWavHeaderPlaceholder() throws IOException {
        // Write 44 bytes placeholder. We'll rewrite it later.
        byte[] header = new byte[44];
        outStream.write(header);
    }

    private void finalizeWavFile() throws Exception {
        outStream.flush();
        long pcmSize = wavFile.length() - 44;

        RandomAccessFile raf = new RandomAccessFile(wavFile, "rw");
        raf.seek(0);

        writeCorrectWavHeader(raf, pcmSize);
        raf.close();

        outStream.close();
    }

    private void writeCorrectWavHeader(RandomAccessFile raf, long pcmSize) throws IOException {
        int sampleRate = this.sampleRate;
        int byteRate = sampleRate * 4;
        int blockAlign = 4;

        raf.writeBytes("RIFF");
        raf.writeInt(Integer.reverseBytes((int)(pcmSize + 36))); // chunk size
        raf.writeBytes("WAVE");

        raf.writeBytes("fmt ");
        raf.writeInt(Integer.reverseBytes(16));     // subchunk1 size
        raf.writeShort(Short.reverseBytes((short)3));  // PCM_FLOAT
        raf.writeShort(Short.reverseBytes((short)1));  // mono
        raf.writeInt(Integer.reverseBytes(sampleRate));
        raf.writeInt(Integer.reverseBytes(byteRate));
        raf.writeShort(Short.reverseBytes((short)blockAlign));
        raf.writeShort(Short.reverseBytes((short)32)); // bits per sample

        raf.writeBytes("data");
        raf.writeInt(Integer.reverseBytes((int)pcmSize));
    }
}
