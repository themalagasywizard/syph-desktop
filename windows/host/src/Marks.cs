using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Text;

namespace Syph.Host;

/// <summary>Set-of-marks: numbered boxes drawn over the screenshot so the model can point at
/// controls by id instead of guessing pixels. Password fields are blacked out first.</summary>
public static class Marks
{
    private static readonly Color[] Palette =
    [
        Color.FromArgb(230, 0, 122, 255), Color.FromArgb(230, 255, 45, 85), Color.FromArgb(230, 52, 199, 89),
        Color.FromArgb(230, 255, 149, 0), Color.FromArgb(230, 175, 82, 222), Color.FromArgb(230, 0, 170, 170),
    ];

    /// <summary>Blacks out password fields in a full-resolution capture whose (0,0) is screen (left, top).</summary>
    public static int Redact(Bitmap bmp, int left, int top, IEnumerable<Element> elements)
    {
        using var g = Graphics.FromImage(bmp);
        var n = 0;
        foreach (var e in elements.Where(e => e.Password))
        {
            g.FillRectangle(Brushes.Black, e.Left - left, e.Top - top, e.W, e.H);
            n++;
        }
        return n;
    }

    public static void Draw(Bitmap image, ImageTransform t, IEnumerable<Element> elements)
    {
        using var g = Graphics.FromImage(image);
        g.SmoothingMode = SmoothingMode.AntiAlias;
        g.TextRenderingHint = TextRenderingHint.AntiAliasGridFit;
        var fontSize = Math.Clamp(image.Width / 110f, 9f, 13f);
        using var font = new Font("Segoe UI", fontSize, FontStyle.Bold, GraphicsUnit.Pixel);
        var i = 0;
        foreach (var e in elements)
        {
            var (x, y) = t.ToImage(e.Left, e.Top);
            var w = e.W / t.Scale; var h = e.H / t.Scale;
            if (x + w < 0 || y + h < 0 || x > image.Width || y > image.Height) continue;
            var color = Palette[i++ % Palette.Length];
            using var pen = new Pen(color, 1.5f);
            g.DrawRectangle(pen, (float)x, (float)y, (float)w, (float)h);
            var label = e.Id.ToString();
            var size = g.MeasureString(label, font);
            // Label sits just inside the top-left corner; flipped inside if it would leave the image.
            var lx = (float)Math.Clamp(x, 0, image.Width - size.Width);
            var ly = (float)Math.Clamp(y - size.Height + 2, 0, image.Height - size.Height);
            using var bg = new SolidBrush(color);
            g.FillRectangle(bg, lx, ly, size.Width, size.Height - 2);
            g.DrawString(label, font, Brushes.White, lx, ly - 1);
        }
    }
}
