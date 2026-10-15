Add-Type -AssemblyName System.Drawing
$p="C:\Users\jorre\AppData\Local\Temp\claude\E--Ldgr\3da7f582-9a49-4fc0-9da5-44332cbe25ab\scratchpad\brand"
function Build($items,$out,$zoom){
 $font=New-Object System.Drawing.Font("Segoe UI",11)
 $cw=760;$ch=120;$rows=@()
 foreach($i in $items){$rows+=,@($i[0],[System.Drawing.Image]::FromFile($i[1]))}
 $bmp=New-Object System.Drawing.Bitmap(($cw*$zoom+20),(($ch*$zoom+28)*$rows.Count+8))
 $g=[System.Drawing.Graphics]::FromImage($bmp);$g.Clear([System.Drawing.Color]::White)
 $g.InterpolationMode='NearestNeighbor';$g.PixelOffsetMode='Half'
 $y=6
 foreach($r in $rows){$g.DrawString($r[0],$font,[System.Drawing.Brushes]::Black,10,$y)
  $g.DrawImage($r[1],(New-Object System.Drawing.Rectangle(10,($y+22),($cw*$zoom),($ch*$zoom))),(New-Object System.Drawing.Rectangle(180,0,$cw,$ch)),'Pixel');$y+=$ch*$zoom+28}
 $bmp.Save($out);$g.Dispose()}
$pv="$p\preview"
$items=@(@("Today","$pv\header-before.png"),@("Earlier H2 (stripped, bars only)","$pv\header-h2b.png"),@("W1  cap 18, 1 backdrop row each side  (1.25x)","$pv\header-w1-1.25.png"),@("W2  cap 20, 1 backdrop row each side  (1.25x)","$pv\header-w2-1.25.png"),@("W3  cap 16, 2 backdrop rows each side  (1.25x)","$pv\header-w3-1.25.png"))
Build $items "$p\header2\header2-options.png" 1
$i2=@(@("W1 at 1.0x","$pv\header-w1-1.png"),@("W2 at 1.0x","$pv\header-w2-1.png"),@("W3 at 1.0x","$pv\header-w3-1.png"))
Build $i2 "$p\header2\header2-1x.png" 1
$i3=@(@("W1 1.25 zoom","$pv\header-w1-1.25.png"),@("W2 1.25 zoom","$pv\header-w2-1.25.png"),@("W3 1.25 zoom","$pv\header-w3-1.25.png"))
Build $i3 "$p\header2\zoom.png" 2
