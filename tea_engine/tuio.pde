import TUIO.*;
// declare a TuioProcessing client
TuioProcessing tuioClient;

// called when a blob is moved
void updateTuioObject (TuioObject tobj) {
  int index = tobj.getSymbolID();
  PVector currPos = new PVector( (tobj.getX()*2.0f)-1.0f, (tobj.getY()*2.0f)-1.0f, 0 ); //tobj.getAngle() not used
  Track currTrack = playlists.playlist.getTrack(index);
  if (currTrack==null) {
    return;
  }
  println(currPos);
  currTrack.setPosition(currPos);
  //---------------------------------------------------------
}
