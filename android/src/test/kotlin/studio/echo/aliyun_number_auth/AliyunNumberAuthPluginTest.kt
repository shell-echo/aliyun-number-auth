package studio.echo.aliyun_number_auth

import com.mobile.auth.gatewayauth.ResultCode
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.mockito.Mockito
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/*
 * This demonstrates a simple unit test of the Kotlin portion of this plugin's implementation.
 *
 * Once you have built the plugin's example app, you can run these tests from the command
 * line by running `./gradlew testDebugUnitTest` in the `example/android/` directory, or
 * you can run them directly from IDEs that support JUnit such as Android Studio.
 */

internal class AliyunNumberAuthPluginTest {
    @Test
    fun environmentCheck_acceptsOnlyEnvironmentSuccessCode() {
        assertTrue(isEnvironmentAvailable(ResultCode.CODE_ERROR_ENV_CHECK_SUCCESS))
        assertFalse(isEnvironmentAvailable(ResultCode.CODE_SUCCESS))
        assertFalse(isEnvironmentAvailable(null))
    }

    @Test
    fun userExitMessage_mapsTerminalAuthPageEvents() {
        assertEquals(ResultCode.MSG_ERROR_USER_CANCEL, userExitMessage(ResultCode.CODE_ERROR_USER_CANCEL))
        assertEquals(ResultCode.MSG_ERROR_USER_SWITCH, userExitMessage(ResultCode.CODE_ERROR_USER_SWITCH))
        assertNull(userExitMessage(ResultCode.CODE_ERROR_USER_LOGIN_BTN))
    }

    @Test
    fun dialogLayout_parsesAndroidSdkFields() {
        val layout = androidDialogLayout(
            mapOf(
                "dialogHeight" to 353.0,
                "tapBackgroundToClose" to true,
                "maskAlpha" to 0.4,
                "numberOffsetY" to 57.0,
                "loginBtnOffsetY" to 120.0,
                "loginBtnHeight" to 55.0,
                "privacyHorizontalPadding" to 28.0,
                "privacyBottomOffset" to 74.0,
            ),
        )

        assertEquals(353, layout.dialogHeight)
        assertTrue(layout.tapBackgroundToClose)
        assertEquals(0.4f, layout.maskAlpha)
        assertEquals(57, layout.numberOffsetY)
        assertEquals(120, layout.loginBtnOffsetY)
        assertEquals(55, layout.loginBtnHeight)
        assertEquals(28, layout.horizontalPadding)
        assertEquals(74, layout.privacyBottomOffset)
    }

    @Test
    fun dialogDragHandle_parsesLogicalPixelsAndVisibility() {
        assertNull(androidDialogDragHandle(emptyMap(), density = 3f))

        val handle = androidDialogDragHandle(
            mapOf(
                "dragHandleVisible" to true,
                "dragHandleColor" to 0xFFE0E0E0,
                "dragHandleWidth" to 36.0,
                "dragHandleHeight" to 4.0,
                "dragHandleTopOffset" to 8.0,
            ),
            density = 3f,
        )

        assertEquals(0xFFE0E0E0.toInt(), handle?.color)
        assertEquals(108, handle?.widthPx)
        assertEquals(12, handle?.heightPx)
        assertEquals(24, handle?.topOffsetPx)
    }

    /**
     * Verify that any unrecognised method name calls result.notImplemented().
     * This test does not require a Flutter engine binding because the else branch
     * in onMethodCall never accesses context, helper, or channel.
     */
    @Test
    fun onMethodCall_unknownMethod_callsNotImplemented() {
        val plugin = AliyunNumberAuthPlugin()
        val call = MethodCall("unknownMethod", null)
        val mockResult: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)
        plugin.onMethodCall(call, mockResult)
        Mockito.verify(mockResult).notImplemented()
    }
}
