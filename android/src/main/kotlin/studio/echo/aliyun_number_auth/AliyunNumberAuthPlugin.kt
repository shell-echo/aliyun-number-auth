package studio.echo.aliyun_number_auth

import android.app.Activity
import android.content.Context
import android.os.Handler
import android.os.Looper
import com.mobile.auth.gatewayauth.PhoneNumberAuthHelper
import com.mobile.auth.gatewayauth.PreLoginResultListener
import com.mobile.auth.gatewayauth.ResultCode
import com.mobile.auth.gatewayauth.TokenResultListener
import com.mobile.auth.gatewayauth.model.TokenRet
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/** AliyunNumberAuthPlugin */
class AliyunNumberAuthPlugin :
    FlutterPlugin,
    MethodCallHandler,
    ActivityAware {
    // The MethodChannel that will the communication between Flutter and native Android
    //
    // This local reference serves to register the plugin with the Flutter Engine and unregister it
    // when the Flutter Engine is detached from the Activity
    private lateinit var channel: MethodChannel
    private lateinit var context: Context
    private var activity: Activity? = null

    private var pendingResult: Result? = null
    private var pendingCheckResult: Result? = null
    private var pendingLoginResult: Result? = null
    private var isInitialized = false
    private val mainHandler = Handler(Looper.getMainLooper())

    private val tokenListener = object : TokenResultListener {
        override fun onTokenSuccess(ret: String) {
            mainHandler.post {
                when {
                    pendingCheckResult != null -> {
                        pendingCheckResult?.success(true)
                        pendingCheckResult = null
                    }
                    pendingLoginResult != null -> {
                        val tokenRet = runCatching { TokenRet.fromJson(ret) }.getOrNull()
                        when (tokenRet?.code) {
                            // Auth page shown — wait for user to tap the login button
                            ResultCode.CODE_START_AUTHPAGE_SUCCESS -> Unit
                            ResultCode.CODE_SUCCESS -> {
                                val token = tokenRet.token
                                if (!token.isNullOrEmpty()) {
                                    pendingLoginResult?.success(token)
                                } else {
                                    pendingLoginResult?.error(CODE_FAILED, "empty token", null)
                                }
                                pendingLoginResult = null
                            }
                            else -> {
                                pendingLoginResult?.error(
                                    tokenRet?.code ?: CODE_FAILED,
                                    tokenRet?.msg ?: ret,
                                    null,
                                )
                                pendingLoginResult = null
                            }
                        }
                    }
                    else -> {
                        val tokenRet = runCatching { TokenRet.fromJson(ret) }.getOrNull()
                        val token = tokenRet?.token
                        if (tokenRet != null && ResultCode.CODE_SUCCESS == tokenRet.code && !token.isNullOrEmpty()) {
                            pendingResult?.success(token)
                        } else {
                            pendingResult?.error(tokenRet?.code ?: CODE_FAILED, tokenRet?.msg ?: ret, null)
                        }
                        pendingResult = null
                    }
                }
            }
        }

        override fun onTokenFailed(ret: String) {
            mainHandler.post {
                val tokenRet = runCatching { TokenRet.fromJson(ret) }.getOrNull()
                val code = tokenRet?.code ?: CODE_FAILED
                val msg = tokenRet?.msg ?: ret
                when {
                    pendingCheckResult != null -> {
                        pendingCheckResult?.success(false)
                        pendingCheckResult = null
                    }
                    pendingLoginResult != null -> {
                        pendingLoginResult?.error(code, msg, null)
                        pendingLoginResult = null
                    }
                    else -> {
                        pendingResult?.error(code, msg, null)
                        pendingResult = null
                    }
                }
            }
        }
    }

    private val helper: PhoneNumberAuthHelper by lazy {
        PhoneNumberAuthHelper.getInstance(context, tokenListener)
    }

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        context = flutterPluginBinding.applicationContext
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "aliyun_number_auth")
        channel.setMethodCallHandler(this)
    }

    // ActivityAware

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivityForConfigChanges() {
        // Config change (rotation etc.) — do NOT cancel the pending login, the SDK handles it
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivity() {
        // Activity fully gone — any in-progress getMobileToken can never complete
        activity = null
        mainHandler.post {
            pendingLoginResult?.error(CODE_CANCELLED, "activity detached", null)
            pendingLoginResult = null
        }
    }

    // Helpers

    private fun requireInit(result: Result): Boolean {
        if (isInitialized) return true
        result.error(CODE_NOT_INIT, "call init() first", null)
        return false
    }

    private fun requireIdle(result: Result): Boolean {
        if (pendingResult == null && pendingCheckResult == null && pendingLoginResult == null) return true
        result.error(CODE_BUSY, "another call is already in progress", null)
        return false
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "init" -> {
                val sk = call.argument<String>("androidSk") ?: ""
                if (sk.isEmpty()) {
                    result.error(CODE_INVALID_ARGS, "androidSk is required", null)
                    return
                }
                helper.setAuthSDKInfo(sk)
                isInitialized = true
                result.success(null)
            }
            "checkEnvAvailable" -> {
                if (!requireInit(result) || !requireIdle(result)) return
                val typeStr = call.argument<String>("type") ?: "loginToken"
                val serviceType = if (typeStr == "verifyToken") {
                    PhoneNumberAuthHelper.SERVICE_TYPE_AUTH
                } else {
                    PhoneNumberAuthHelper.SERVICE_TYPE_LOGIN
                }
                pendingCheckResult = result
                try {
                    helper.checkEnvAvailable(serviceType)
                } catch (e: Exception) {
                    pendingCheckResult?.error(CODE_FAILED, e.message, null)
                    pendingCheckResult = null
                }
            }
            "preload" -> {
                if (!requireInit(result)) return
                val ms = call.argument<Int>("timeout") ?: 3000
                helper.accelerateVerify(ms, object : PreLoginResultListener {
                    override fun onTokenSuccess(vendor: String?) {}
                    override fun onTokenFailed(vendor: String?, errorMsg: String?) {}
                })
                result.success(null)
            }
            "preloadLogin" -> {
                if (!requireInit(result)) return
                val ms = call.argument<Int>("timeout") ?: 3000
                helper.accelerateLoginPage(ms, object : PreLoginResultListener {
                    override fun onTokenSuccess(vendor: String?) {}
                    override fun onTokenFailed(vendor: String?, errorMsg: String?) {}
                })
                result.success(null)
            }
            "getVerifyToken" -> {
                if (!requireInit(result) || !requireIdle(result)) return
                val ms = call.argument<Int>("timeout") ?: 10000
                pendingResult = result
                try {
                    helper.getVerifyToken(ms)
                } catch (e: Exception) {
                    pendingResult?.error(CODE_FAILED, e.message, null)
                    pendingResult = null
                }
            }
            "getMobileToken" -> {
                if (!requireInit(result) || !requireIdle(result)) return
                val act = activity
                if (act == null) {
                    result.error(CODE_NO_ACTIVITY, "no active activity", null)
                    return
                }
                val ms = call.argument<Int>("timeout") ?: 10000
                pendingLoginResult = result
                try {
                    helper.getLoginToken(act, ms)
                } catch (e: Exception) {
                    pendingLoginResult?.error(CODE_FAILED, e.message, null)
                    pendingLoginResult = null
                }
            }
            else -> result.notImplemented()
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        pendingCheckResult?.error(CODE_CANCELLED, "plugin detached", null)
        pendingCheckResult = null
        pendingResult?.error(CODE_CANCELLED, "plugin detached", null)
        pendingResult = null
        pendingLoginResult?.error(CODE_CANCELLED, "plugin detached", null)
        pendingLoginResult = null
    }

    companion object {
        private const val CODE_INVALID_ARGS = "INVALID_ARGS"
        private const val CODE_NOT_INIT = "NOT_INITIALIZED"
        private const val CODE_BUSY = "BUSY"
        private const val CODE_FAILED = "FAILED"
        private const val CODE_CANCELLED = "CANCELLED"
        private const val CODE_NO_ACTIVITY = "NO_ACTIVITY"
    }
}
