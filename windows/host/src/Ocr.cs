using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices.WindowsRuntime;
using Windows.Graphics.Imaging;
using Windows.Media.Ocr;

namespace Syph.Host;

public sealed record OcrLine(string Text, int X, int Y, int W, int H, int Left, int Top);

/// <summary>On-device text recognition with Windows.Media.Ocr; boxes come back in screen pixels.</summary>
public static class Ocr
{
    private static OcrEngine? _engine;
    private static bool _tried;

    public static string? Unavailable { get; private set; }

    private static OcrEngine? Engine()
    {
        if (_tried) return _engine;
        _tried = true;
        _engine = OcrEngine.TryCreateFromUserProfileLanguages();
        if (_engine is null)
        {
            var english = new Windows.Globalization.Language("en-US");
            if (OcrEngine.IsLanguageSupported(english)) _engine = OcrEngine.TryCreateFromLanguage(english);
        }
        if (_engine is null) Unavailable = "Windows has no OCR language installed; add one in Settings > Time & language > Language.";
        return _engine;
    }

    /// <summary>Recognises text in a bitmap whose pixel (0,0) sits at screen (originX, originY).</summary>
    public static List<OcrLine> Read(Bitmap bmp, int originX, int originY)
    {
        var engine = Engine();
        if (engine is null) return [];
        // Windows OCR has a maximum image dimension; scale down past it and scale boxes back up.
        double scale = 1;
        Bitmap source = bmp;
        var max = (int)OcrEngine.MaxImageDimension;
        if (bmp.Width > max || bmp.Height > max)
        {
            scale = Math.Max((double)bmp.Width / max, (double)bmp.Height / max);
            source = new Bitmap(bmp, new Size((int)(bmp.Width / scale), (int)(bmp.Height / scale)));
        }
        try
        {
            using var soft = ToSoftwareBitmap(source);
            var result = engine.RecognizeAsync(soft).AsTask().GetAwaiter().GetResult();
            var lines = new List<OcrLine>();
            foreach (var line in result.Lines)
            {
                double minX = double.MaxValue, minY = double.MaxValue, maxX = 0, maxY = 0;
                foreach (var word in line.Words)
                {
                    var r = word.BoundingRect;
                    minX = Math.Min(minX, r.X); minY = Math.Min(minY, r.Y);
                    maxX = Math.Max(maxX, r.X + r.Width); maxY = Math.Max(maxY, r.Y + r.Height);
                }
                if (line.Words.Count == 0) continue;
                int left = originX + (int)(minX * scale), top = originY + (int)(minY * scale);
                int w = (int)((maxX - minX) * scale), h = (int)((maxY - minY) * scale);
                lines.Add(new OcrLine(line.Text, left + w / 2, top + h / 2, w, h, left, top));
            }
            // Reading order: rows top to bottom, then left to right.
            return lines.OrderBy(l => l.Y / 10).ThenBy(l => l.Left).ToList();
        }
        finally
        {
            if (!ReferenceEquals(source, bmp)) source.Dispose();
        }
    }

    private static SoftwareBitmap ToSoftwareBitmap(Bitmap bmp)
    {
        var rect = new Rectangle(0, 0, bmp.Width, bmp.Height);
        var data = bmp.LockBits(rect, ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
        try
        {
            var bytes = new byte[data.Stride * data.Height];
            System.Runtime.InteropServices.Marshal.Copy(data.Scan0, bytes, 0, bytes.Length);
            // Format32bppArgb is laid out B,G,R,A in memory, which is Bgra8.
            if (data.Stride != bmp.Width * 4)
            {
                var packed = new byte[bmp.Width * 4 * bmp.Height];
                for (int y = 0; y < bmp.Height; y++) Buffer.BlockCopy(bytes, y * data.Stride, packed, y * bmp.Width * 4, bmp.Width * 4);
                bytes = packed;
            }
            return SoftwareBitmap.CreateCopyFromBuffer(bytes.AsBuffer(), BitmapPixelFormat.Bgra8, bmp.Width, bmp.Height, BitmapAlphaMode.Premultiplied);
        }
        finally
        {
            bmp.UnlockBits(data);
        }
    }
}
