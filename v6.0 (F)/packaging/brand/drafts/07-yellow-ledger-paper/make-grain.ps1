param([string]$Out, [int]$Size = 512, [int]$Seed = 7)
Add-Type -AssemblyName System.Drawing
Add-Type -TypeDefinition @"
using System; using System.Drawing; using System.Drawing.Imaging;
public static class Grain {
  public static void Make(string path, int n, int seed) {
    var r = new Random(seed);
    float[] v = new float[n*n];
    // fine noise (sum of 3 uniforms ~ gaussian), sigma ~ 12
    for (int i=0;i<v.Length;i++) v[i] = (float)((r.NextDouble()+r.NextDouble()+r.NextDouble()-1.5)*20.0);
    // soft 1px blur-ish pass on a copy so grain is not pure pixel static: mix with neighbour (wrapping)
    float[] w = new float[n*n];
    for (int y=0;y<n;y++) for (int x=0;x<n;x++) {
      int xl=(x+n-1)%n, xr=(x+1)%n, yu=(y+n-1)%n, yd=(y+1)%n;
      w[y*n+x] = 0.55f*v[y*n+x] + 0.1125f*(v[y*n+xl]+v[y*n+xr]+v[yu*n+x]+v[yd*n+x]);
    }
    v = w;
    // low-frequency blotches (wrapping cosine sums), very faint
    for (int k=0;k<6;k++) {
      double fx = r.Next(1,4), fy = r.Next(1,4), ph = r.NextDouble()*6.28, ph2 = r.NextDouble()*6.28, a = 3.0;
      for (int y=0;y<n;y++) for (int x=0;x<n;x++)
        v[y*n+x] += (float)(a*Math.Cos(2*Math.PI*(fx*x/n)+ph)*Math.Cos(2*Math.PI*(fy*y/n)+ph2));
    }
    // horizontal fibre streaks, wrapping both ways
    int fibres = n*n/2200;
    for (int f=0; f<fibres; f++) {
      int y0 = r.Next(n), x0 = r.Next(n), len = r.Next(18, 90);
      float amp = (float)((r.NextDouble()<0.5?-1:1)*(6+r.NextDouble()*10));
      double drift = (r.NextDouble()-0.5)*0.06;
      for (int i=0;i<len;i++) {
        double t = Math.Sin(Math.PI*i/len);
        int x = (x0+i)%n; int y = ((int)Math.Round(y0+drift*i)%n+n)%n;
        v[y*n+x] += (float)(amp*t);
      }
    }
    var bmp = new Bitmap(n,n,PixelFormat.Format24bppRgb);
    bmp.SetResolution(72,72);
    var bd = bmp.LockBits(new Rectangle(0,0,n,n), ImageLockMode.WriteOnly, PixelFormat.Format24bppRgb);
    byte[] buf = new byte[bd.Stride*n];
    for (int y=0;y<n;y++) for (int x=0;x<n;x++) {
      int g = (int)Math.Round(128 + v[y*n+x]); if (g<0) g=0; if (g>255) g=255;
      int o = y*bd.Stride + x*3; buf[o]=(byte)g; buf[o+1]=(byte)g; buf[o+2]=(byte)g;
    }
    System.Runtime.InteropServices.Marshal.Copy(buf,0,bd.Scan0,buf.Length);
    bmp.UnlockBits(bd); bmp.Save(path, ImageFormat.Png); bmp.Dispose();
  }
}
"@ -ReferencedAssemblies System.Drawing
[Grain]::Make($Out, $Size, $Seed)
