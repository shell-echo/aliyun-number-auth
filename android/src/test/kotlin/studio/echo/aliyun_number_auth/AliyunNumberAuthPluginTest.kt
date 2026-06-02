package studio.echo.aliyun_number_auth

import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.mockito.Mockito
import kotlin.test.Test

/*
 * This demonstrates a simple unit test of the Kotlin portion of this plugin's implementation.
 *
 * Once you have built the plugin's example app, you can run these tests from the command
 * line by running `./gradlew testDebugUnitTest` in the `example/android/` directory, or
 * you can run them directly from IDEs that support JUnit such as Android Studio.
 */

internal class AliyunNumberAuthPluginTest {
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
