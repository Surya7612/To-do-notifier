/**
 * Little-endian PCM16 mono → WAV buffer for OpenAI Whisper.
 * @param {Buffer} pcmBuf
 * @param {number} sampleRate
 */
function pcm16ToWavBuffer(pcmBuf, sampleRate) {
  const dataSize = pcmBuf.length;
  const buf = Buffer.alloc(44 + dataSize);
  buf.write("RIFF", 0);
  buf.writeUInt32LE(36 + dataSize, 4);
  buf.write("WAVE", 8);
  buf.write("fmt ", 12);
  buf.writeUInt32LE(16, 16);
  buf.writeUInt16LE(1, 20); // PCM
  buf.writeUInt16LE(1, 22); // mono
  buf.writeUInt32LE(sampleRate, 24);
  buf.writeUInt32LE(sampleRate * 2, 28);
  buf.writeUInt16LE(2, 32);
  buf.writeUInt16LE(16, 34);
  buf.write("data", 36);
  buf.writeUInt32LE(dataSize, 40);
  pcmBuf.copy(buf, 44);
  return buf;
}

module.exports = { pcm16ToWavBuffer };
