//just for nice visualization - draw outline around speakers

import java.util.*; //for Vector type

class ConvexHull {

  PShape convexHull;
  float convexHullDia;//max distance from center to outermost vertex of the convexHull shape - used for max range of neighbour distance between boids
  PVector convexHullCentroid;
  boolean is2D = false;

  ConvexHull() {
  }
  //-------------------------
  PShape calculateConvexHull(ArrayList<PVector> points) {
    boolean _posZisZero = true;
    for (int i=0; i<points.size(); i++) {

      float[] loc = points.get(i).array();
      if ( loc.length<3 ) { //if only 2 axis are defined
        this.is2D = true; //must be 2D
      } else {
        if ( points.get(i).z != 0 ) {
          _posZisZero = false; //check if all z axis are 0
        }
      }
    }

    if (_posZisZero) { //all z values are 0
      this.is2D = true;
    }

    if (this.is2D) {
      PVector[] pts2D = new PVector[points.size()];
      for (int i = 0; i < points.size(); i++) {
        pts2D[i] = new PVector((float) points.get(i).x, (float) points.get(i).y);
      }
      this.convexHull = this.calculateConvexHull2D(pts2D);
      this.convexHullCentroid = this.getShapeCentroid2D(this.convexHull);
    } else {
      this.convexHull = this.calculateConvexHull3D(points);
      this.convexHullCentroid = this.getShapeCentroid3D(this.convexHull);
      //println("calculated 3D centroid: "+this.convexHullCentroid);
    }

    this.convexHullDia = this.getShapeDia(this.convexHull);

    return this.convexHull;
  }
  //-----------------------------
  float getShapeDia(PShape s) {
    float max = 0;
    PVector centr = new PVector(0, 0, 0);

    // First, check the vertices of the shape itself
    for (int i = 0; i < s.getVertexCount(); i++) {
      PVector pos = s.getVertex(i);
      float d = pos.dist(centr);
      if (d > max) max = d;
    }

    // Then, check child shapes (if any)
    for (int c = 0; c < s.getChildCount(); c++) {
      PShape f = s.getChild(c);
      for (int i = 0; i < f.getVertexCount(); i++) {
        PVector pos = f.getVertex(i);
        float d = pos.dist(centr);
        if (d > max) max = d;
      }
    }

    return max * 2; // diameter
  }
  //---------------------------------
  PVector getShapeCentroid3D(PShape s) {
    //println("get centroid");
    PVector weightedCenteresSum = null;
    float areaSum = 0.0;
    //ArrayList<PVector>centers = new ArrayList<PVector>();
    for (int ch = 0; ch < s.getChildCount(); ch++) { //for each face
      PVector face[] = new PVector[3];
      PShape currFace = s.getChild(ch);
      for (int i = 0; i < currFace.getVertexCount(); i++) {//for each vertex inside face - assumes triangle
        if (i<3) {
          face[i] = currFace.getVertex(i);
        } else {
          println("eror - getShapeCentroid() fce expects triangle face");
        }
      }
      PVector currCenter = findCentroid(face[0], face[1], face[2]);
      float[] triSides = getTriangleSides( face[0], face[1], face[2] );
      float triArea = triangleArea( triSides[0], triSides[1], triSides[2]);
      //multiply centroid by scalar area
      PVector weightedCenter = currCenter.mult(triArea);

      if ( weightedCenteresSum == null ) {
        weightedCenteresSum = weightedCenter;
      } else {
        weightedCenteresSum.add(weightedCenter);
      }
      areaSum += triArea;
    }
    //r_c = sum(r_i * m_i) / sum(m_i)
    PVector centroid = weightedCenteresSum.div(areaSum);
    return centroid;
  }
  //-------------------------------------
  PVector getShapeCentroid2D(PShape s) {
    float signedArea = 0;
    float cx = 0;
    float cy = 0;

    // We assume 's' is a single polygon (not GROUP with children)
    int vertexCount = s.getVertexCount();
    if (vertexCount < 3) {
      println("Error: Shape has fewer than 3 vertices — cannot compute centroid.");
      return new PVector(0, 0);
    }

    for (int i = 0; i < vertexCount; i++) {
      PVector p0 = s.getVertex(i);
      PVector p1 = s.getVertex((i + 1) % vertexCount);
      float cross = p0.x * p1.y - p1.x * p0.y;
      signedArea += cross;
      cx += (p0.x + p1.x) * cross;
      cy += (p0.y + p1.y) * cross;
    }

    signedArea *= 0.5;
    cx /= (6.0 * signedArea);
    cy /= (6.0 * signedArea);

    return new PVector(cx, cy);
  }

  //-------------------------
  //Graham Scan lines algorithm naively implemented here in Java ?
  PShape calculateConvexHull2D(PVector[] points) {
    int n = points.length;
    if (n < 3) {
      return null;
    }
    Vector<PVector> hull = new Vector<PVector>();
    // Find leftmost point
    int l = 0;
    for (int i = 1; i < n; i++) if (points[i].x < points[l].x) l = i;

    int p = l, q;
    do {
      hull.add(points[p]);
      q = (p + 1) % n;
      for (int i = 0; i < n; i++) {
        if (orientation(points[p], points[i], points[q]) == 2)
          q = i;
      }
      p = q;
    } while (p != l);

    // visualize hull as shape
    PShape convexHull = createShape();
    convexHull.beginShape();
    convexHull.stroke(255, 255, 0);
    convexHull.strokeWeight(0.01); //normalized
    convexHull.fill(255, 255, 0, 50);
    convexHull.normal(0, 0, 1);
    for (PVector pt : hull) convexHull.vertex(pt.x, pt.y);
    convexHull.endShape(CLOSE);

    return convexHull;
  }
  //-------------------------
  // Orientation helper (for 2D hull)
  int orientation(PVector p, PVector q, PVector r) {
    float val = (q.y - p.y) * (r.x - q.x) - (q.x - p.x) * (r.y - q.y);
    if (val == 0) return 0;
    return (val > 0) ? 1 : 2;
  }
  //-------------------------

  //uses quickHUll library
  PShape calculateConvexHull3D(ArrayList<PVector> points) {

    QuickHull3D hull = new QuickHull3D(); //init quickhull
    //we need another 3d point format for this lib - convert PVector to Point3d
    Point3d[] p3points = new Point3d[points.size()];
    for (int i=0; i<points.size(); i++) {
      p3points[i] = new Point3d (points.get(i).x, points.get(i).y, points.get(i).z);
    }

    PShape convexHull = createShape(GROUP);

    if (hull.myCheck(p3points, p3points.length) == true) {
      hull.build(p3points);  //build hull
      hull.triangulate();  //triangulate faces
      Point3d[] vertices = hull.getVertices();  //get vertices

      int[][] faceIndices = hull.getFaces();
      //run through faces (each point on each face), and draw them
      for (int i = 0; i < faceIndices.length; i++) {
        PVector[] currFace = new PVector[3];
        for (int k = 0; k < faceIndices[i].length; k++) {
          //get points that correspond to each face
          Point3d pnt2 = vertices[faceIndices[i][k]];
          currFace[k] = new PVector( (float)pnt2.x, (float)pnt2.y, (float)pnt2.z );
          //convexHull.vertex(x, y, z);
        }
        //TRIANGLES
        PShape newFace = createShape();
        newFace.beginShape();
        //newFace.noFill();
        color randCol = color( random(0, 255), random(0, 255), random(0, 255) );
        newFace.fill( randCol, 50 );
        
        newFace.noStroke();
        //newFace.stroke( randCol );
        newFace.strokeWeight(0.01); //camera space not pixel space
        PVector normal = calculateNormal(currFace);
        newFace.normal(normal.x, normal.y, normal.z); //differs to automatic println( tri.getNormal(0) );


        for (int f=0; f<currFace.length; f++) {
          newFace.vertex( currFace[f].x, currFace[f].y, currFace[f].z);
        }



        newFace.endShape();
        convexHull.addChild(newFace);
      }
      //this.convexHullCentroid.mult( getRenderScale() );
      //println("child count: "+convexHull.getChildCount());
      return convexHull;
    }
    return null;
  }

  //-------------------------
}


boolean isInside2DPolygon(PVector v, PShape shape, float safeMarginFromEdges) {
  // ------------- 2D POLYGON CHECK -------------
  int vertexCount = shape.getVertexCount();
  boolean inside = false;
  for (int i = 0, j = vertexCount - 1; i < vertexCount; j = i++) {
    PVector vi = shape.getVertex(i).copy();
    PVector vj = shape.getVertex(j).copy();

    // Check if the point is within polygon edges (ray casting algorithm)
    if (((vi.y > v.y) != (vj.y > v.y)) &&
      (v.x < (vj.x - vi.x) * (v.y - vi.y) / (vj.y - vi.y + 0.00001) + vi.x)) {
      inside = !inside;
    }
  }
  // Optional: safe margin check — shrink polygon slightly (simple approximation)
  if (inside) {
    // Check distance to edges for safe margin
    for (int i = 0, j = vertexCount - 1; i < vertexCount; j = i++) {
      PVector vi = shape.getVertex(i).copy();
      PVector vj = shape.getVertex(j).copy();
      float distToEdge = abs((vj.y - vi.y) * v.x - (vj.x - vi.x) * v.y + vj.x * vi.y - vj.y * vi.x)
        / vi.dist(vj);
      if (distToEdge < safeMarginFromEdges) {
        return false;
      }
    }
  }
  return inside;
}


boolean isInside3DPolygon(PVector v, PShape shape, float safeMarginFromEdges) {
  //iterate over all faces - guaranteed to be triangles
  for (int f=0; f< shape.getChildCount(); f++ ) { //will not work for 2D ???
    PShape currFace = shape.getChild(f);
    PVector currNormal = currFace.getNormal(0);
    PVector currPointOnFace = currFace.getVertex(0);
    //calculate perpendicular distance from boid to infinite plane defined by face triangle and normal - signed version!
    //if it is negative it means it is outside the plane's normal direction ie outiside the convex shape!
    float currDist =  shortestDistanceToPlane(currPointOnFace, currNormal, v);
    //if it is outside...
    //if (currDist< 0 ) {
    if (currDist< safeMarginFromEdges ) { //create safe 10% margin from edges - we want the food not to apear directly on surfaces
      return false;
    }
  }
  return true;
}


//Processing does not correctly render stroke() inside the PShape face...so we have to do it ourselves
void renderConvexHullEdges(PGraphics screen, PShape convexHull) {
  if (convexHull == null) return;

  for (int i = 0; i < convexHull.getChildCount(); i++) {
    PShape face = convexHull.getChild(i);

    // Get the fill color of the face
    int faceColor = face.getFill(0); // vertex index 0, all vertices have same fill in our case

    // Set stroke to face color
    //screen.stroke((faceColor & 0x00FFFFFF) | 0xFF000000); //100% alpha
    screen.stroke(faceColor);
    screen.strokeWeight(0.01); // adjust pixel thickness

    // Draw edges of the triangle
    int vCount = face.getVertexCount();
    for (int j = 0; j < vCount; j++) {
      PVector a = face.getVertex(j);
      PVector b = face.getVertex((j + 1) % vCount);
      screen.line(a.x, a.y, a.z, b.x, b.y, b.z);
    }
  }
}
