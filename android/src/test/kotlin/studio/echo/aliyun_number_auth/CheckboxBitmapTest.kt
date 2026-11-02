package studio.echo.aliyun_number_auth

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.test.assertEquals
import kotlin.test.assertTrue

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], manifest = Config.NONE)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class CheckboxBitmapTest {
    @Test
    fun uncheckedBorderRetainsColorAfterNativeCompositing() {
        // Opaque light/dark surfaces include warm, neutral and notebook samples.
        val samples = listOf(
            0xFFF0B487 to 0xFF24211D, 0xFFA04715 to 0xFFFBF7EF,
            0xFFE5E5E5 to 0xFF0A0A0A, 0xFF000000 to 0xFFFFFFFF,
            0xFFF0B487 to 0xFF25211D, 0xFFA04715 to 0xFFFBF6EC,
        )
        for ((color, background) in samples) {
            for (size in listOf(40, 60, 84)) {
                for (circle in listOf(false, true)) {
                    val image = checkboxBitmap(false, color.toInt(), background.toInt(), circle, size)
                    val x = (size * 0.06f).toInt()
                    val y = size / 2
                    assertEquals(255, Color.alpha(image.getPixel(x, y)))
                    assertEquals(0, Color.alpha(image.getPixel(y, y)), "no fixed white fill")
                    val result = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
                    val canvas = Canvas(result)
                    canvas.drawColor(background.toInt())
                    canvas.drawBitmap(image, 0f, 0f, null)
                    val edge = result.getPixel(x, y)
                    val surface = result.getPixel(y, y)
                    assertEquals(color.toInt(), edge, "final border must not be diluted")
                    assertEquals(background.toInt(), surface)
                    assertTrue(contrast(edge, surface) >= 3, "final native raster contrast")
                    val checked = checkboxBitmap(true, color.toInt(), background.toInt(), circle, size)
                    assertEquals(255, Color.alpha(checked.getPixel(y, size / 4)))
                }
            }
        }
    }

    private fun contrast(a: Int, b: Int): Double {
        fun linear(value: Int): Double {
            val v = value / 255.0
            return if (v <= 0.04045) v / 12.92 else ((v + 0.055) / 1.055).pow(2.4)
        }
        fun luminance(c: Int) = linear(Color.red(c)) * 0.2126 +
            linear(Color.green(c)) * 0.7152 + linear(Color.blue(c)) * 0.0722
        val x = luminance(a)
        val y = luminance(b)
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }
}
