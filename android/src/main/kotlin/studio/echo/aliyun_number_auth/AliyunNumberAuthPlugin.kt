package studio.echo.aliyun_number_auth

import android.app.Activity
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.BitmapShader
import android.graphics.Canvas
import android.graphics.ColorFilter
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PixelFormat
import android.graphics.Rect
import android.graphics.RectF
import android.graphics.Shader
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.ColorDrawable
import android.graphics.drawable.Drawable
import android.graphics.drawable.GradientDrawable
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import com.mobile.auth.gatewayauth.AuthUIConfig
import com.mobile.auth.gatewayauth.AuthUIControlClickListener
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
class AliyunNumberAuthPlugin internal constructor(
    private val testMainDispatcher: ((() -> Unit) -> Unit)?,
) :
    FlutterPlugin,
    MethodCallHandler,
    ActivityAware {

    constructor() : this(null)

    private lateinit var channel: MethodChannel
    private lateinit var context: Context
    private var activity: Activity? = null

    private var privacyVCIsCustomized = false
    private var suspendDisMissVC = false
    // SDK listeners capture the originating Result before the call starts;
    // completion is dispatched to main and checks that this Result is still live.
    @Volatile internal var pendingCheckResult: Result? = null
    @Volatile internal var pendingResult: Result? = null        // for getVerifyToken
    @Volatile internal var pendingLoginResult: Result? = null   // for getMobileToken
    private var isInitialized = false
    private val mainHandler by lazy { Handler(Looper.getMainLooper()) }

    private fun onMain(action: () -> Unit) {
        val dispatcher = testMainDispatcher
        if (dispatcher != null) dispatcher(action) else mainHandler.post(action)
    }

    // Bind before invoking the SDK. Taking snapshots only when an SDK callback
    // arrives would bind an expired response to whichever request is current then.
    internal fun createTokenListener(
        checkSnap: Result? = null,
        loginSnap: Result? = null,
        tokenSnap: Result? = null,
    ): TokenResultListener = object : TokenResultListener {
        override fun onTokenSuccess(ret: String) {
            onMain {
                when {
                    checkSnap != null && pendingCheckResult === checkSnap -> {
                        // checkEnvAvailable has its own success code (600024). The token
                        // success code (600000) belongs to getMobileToken/getVerifyToken.
                        val tokenRet = runCatching { TokenRet.fromJson(ret) }.getOrNull()
                        val available = isEnvironmentAvailable(tokenRet?.code)
                        pendingCheckResult = null
                        checkSnap.success(available)
                    }
                    loginSnap != null && pendingLoginResult === loginSnap -> {
                        val tokenRet = runCatching { TokenRet.fromJson(ret) }.getOrNull()
                        when (tokenRet?.code) {
                            // Auth page successfully shown — surface as onAuthPageShown
                            // so callers can dismiss their own loading state, log analytics,
                            // etc. Token fetch is still pending the user's login tap.
                            // Intermediate event — do NOT clear pendingLoginResult.
                            ResultCode.CODE_START_AUTHPAGE_SUCCESS -> {
                                channel.invokeMethod("onAuthPageShown", null)
                            }
                            ResultCode.CODE_SUCCESS -> {
                                val token = tokenRet.token
                                pendingLoginResult = null
                                if (!token.isNullOrEmpty()) {
                                    loginSnap.success(token)
                                } else {
                                    loginSnap.error(CODE_FAILED, "empty token", null)
                                }
                            }
                            else -> {
                                pendingLoginResult = null
                                loginSnap.error(
                                    tokenRet?.code ?: CODE_FAILED,
                                    tokenRet?.msg ?: ret,
                                    null,
                                )
                            }
                        }
                    }
                    tokenSnap != null && pendingResult === tokenSnap -> {
                        val tokenRet = runCatching { TokenRet.fromJson(ret) }.getOrNull()
                        val token = tokenRet?.token
                        pendingResult = null
                        if (tokenRet != null && ResultCode.CODE_SUCCESS == tokenRet.code && !token.isNullOrEmpty()) {
                            tokenSnap.success(token)
                        } else {
                            tokenSnap.error(tokenRet?.code ?: CODE_FAILED, tokenRet?.msg ?: ret, null)
                        }
                    }
                    // No matching live pending — event arrived after a detach /
                    // dismiss / watchdog already resolved the Future. Drop it.
                }
            }
        }

        override fun onTokenFailed(ret: String) {
            onMain {
                val tokenRet = runCatching { TokenRet.fromJson(ret) }.getOrNull()
                val code = tokenRet?.code ?: CODE_FAILED
                val msg = tokenRet?.msg ?: ret
                when {
                    checkSnap != null && pendingCheckResult === checkSnap -> {
                        pendingCheckResult = null
                        checkSnap.success(false)
                    }
                    loginSnap != null && pendingLoginResult === loginSnap -> {
                        pendingLoginResult = null
                        loginSnap.error(code, msg, null)
                    }
                    tokenSnap != null && pendingResult === tokenSnap -> {
                        pendingResult = null
                        tokenSnap.error(code, msg, null)
                    }
                }
            }
        }
    }

    private val helper: PhoneNumberAuthHelper by lazy {
        PhoneNumberAuthHelper.getInstance(context, createTokenListener())
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
        // Activity fully gone — cancel any in-progress getMobileToken synchronously.
        // We are already on the main thread so mainHandler.post is not needed and
        // would leave a window where a racing tokenListener callback could call the
        // result a second time before the post executes.
        val hadLogin = pendingLoginResult != null
        pendingLoginResult?.error(CODE_CANCELLED, "activity detached", null)
        pendingLoginResult = null
        // Mirror the iOS behavior: if a login was in flight the auth page is
        // (or was) on top of the now-departing activity — quit it so the user
        // doesn't return to an orphan SDK page after the next attach.
        if (hadLogin) runCatching { helper.quitLoginPage() }
        activity = null
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
                // `helper` is `by lazy` and `setAuthSDKInfo` itself is fire-and-forget
                // (Aliyun's Android SDK has no init-result callback). Wrap both so a
                // throw at first-access (PhoneNumberAuthHelper.getInstance failing on
                // missing resources / misconfigured proguard) never leaves the Dart
                // init() Future hanging.
                //
                // NOTE: success here is OPTIMISTIC — `setAuthSDKInfo` accepts any
                // string without validation. A wrong key surfaces later as a
                // `checkEnvAvailable`/`getMobileToken` failure (e.g. code 600017).
                try {
                    helper.setAuthSDKInfo(sk)
                    isInitialized = true
                    result.success(null)
                } catch (e: Throwable) {
                    result.error(CODE_FAILED, "init failed: ${e.message}", null)
                }
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
                    helper.setAuthListener(createTokenListener(checkSnap = result))
                    helper.checkEnvAvailable(serviceType)
                    mainHandler.postDelayed({
                        if (pendingCheckResult === result) {
                            pendingCheckResult = null
                            result.error("600015", "environment check did not respond within 15s", null)
                        }
                    }, 15_000)
                } catch (e: Exception) {
                    pendingCheckResult?.error(CODE_FAILED, e.message, null)
                    pendingCheckResult = null
                }
            }
            "preload" -> {
                if (!requireInit(result)) return
                val ms = call.argument<Int>("timeout") ?: 3000
                try {
                    helper.accelerateVerify(ms, object : PreLoginResultListener {
                        override fun onTokenSuccess(vendor: String?) {}
                        override fun onTokenFailed(vendor: String?, errorMsg: String?) {}
                    })
                    result.success(null)
                } catch (e: Throwable) {
                    result.error(CODE_FAILED, "preload failed: ${e.message}", null)
                }
            }
            "preloadLogin" -> {
                if (!requireInit(result)) return
                val ms = call.argument<Int>("timeout") ?: 3000
                try {
                    helper.accelerateLoginPage(ms, object : PreLoginResultListener {
                        override fun onTokenSuccess(vendor: String?) {}
                        override fun onTokenFailed(vendor: String?, errorMsg: String?) {}
                    })
                    result.success(null)
                } catch (e: Throwable) {
                    result.error(CODE_FAILED, "preloadLogin failed: ${e.message}", null)
                }
            }
            "getVerifyToken" -> {
                if (!requireInit(result) || !requireIdle(result)) return
                val ms = call.argument<Int>("timeout") ?: 10000
                pendingResult = result
                try {
                    helper.setAuthListener(createTokenListener(tokenSnap = result))
                    helper.getVerifyToken(ms)
                    mainHandler.postDelayed({
                        if (pendingResult === result) {
                            pendingResult = null
                            result.error("600015", "verification did not respond within timeout", null)
                        }
                    }, ms.toLong().coerceAtLeast(0) + 1_000)
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
                @Suppress("UNCHECKED_CAST")
                val uiConfig = call.argument<Map<String, Any>>("uiConfig")
                privacyVCIsCustomized = uiConfig?.get("privacyVCIsCustomized") as? Boolean ?: false
                suspendDisMissVC = uiConfig?.get("suspendDisMissVC") as? Boolean ?: false
                pendingLoginResult = result
                try {
                    helper.setAuthListener(createTokenListener(loginSnap = result))
                    // Drop any view-overlay registrations from a previous call so
                    // they don't accumulate. We never call addAuthRegistViewConfig
                    // ourselves, but a host app that registers custom views via the
                    // PhoneNumberAuthHelper singleton between Flutter calls could
                    // leak them across getMobileToken invocations otherwise. The
                    // Aliyun demo calls these unconditionally for the same reason.
                    runCatching { helper.removeAuthRegisterXmlConfig() }
                    runCatching { helper.removeAuthRegisterViewConfig() }
                    runCatching { helper.removePrivacyAuthRegisterViewConfig() }
                    runCatching { helper.removePrivacyRegisterXmlConfig() }
                    // Always rebuild the AuthUIConfig — otherwise the previous call's
                    // styles (button text, protocols, checkbox drawables, etc.) silently
                    // leak into a subsequent call that passes uiConfig=null.
                    // Empty map yields all defaults because every read uses `?: default`.
                    buildAndSetAuthUIConfig(uiConfig ?: emptyMap())
                    // registerUIClickListener must run regardless of whether uiConfig is
                    // provided — otherwise onLoginButtonTap / onPrivacyLinkTap /
                    // onSuspendedDismiss callbacks silently never fire.
                    registerUIClickListener()
                    if (suspendDisMissVC) helper.userControlAuthPageCancel()
                    helper.getLoginToken(act, ms)
                } catch (e: Exception) {
                    pendingLoginResult?.error(CODE_FAILED, e.message, null)
                    pendingLoginResult = null
                }
            }
            "dismissLoginPage" -> {
                pendingLoginResult?.error(CODE_CANCELLED, "dismissed programmatically", null)
                pendingLoginResult = null
                runCatching { helper.quitLoginPage() }
                result.success(null)
            }
            "setCheckboxChecked" -> {
                if (!requireInit(result)) return
                val checked = call.argument<Boolean>("checked") ?: false
                runCatching { helper.setProtocolChecked(checked) }
                result.success(null)
            }
            "isCheckboxChecked" -> {
                if (!requireInit(result)) return
                val checked = runCatching { helper.queryCheckBoxIsChecked() }.getOrDefault(false)
                result.success(checked)
            }
            "animatePrivacyText" -> {
                if (!requireInit(result)) return
                runCatching { helper.privacyAnimationStart() }
                result.success(null)
            }
            "animateCheckbox" -> {
                if (!requireInit(result)) return
                runCatching { helper.checkBoxAnimationStart() }
                result.success(null)
            }
            "closePrivacyAlertDialog" -> {
                if (!requireInit(result)) return
                runCatching { helper.quitPrivacyPage() }
                result.success(null)
            }
            "hideLoginLoading" -> {
                if (!requireInit(result)) return
                runCatching { helper.hideLoginLoading() }
                result.success(null)
            }
            "getSDKVersion" -> {
                // Surface a hard failure if the SDK API name changed, instead of returning
                // a stale hard-coded string the caller would mistake for the real version.
                try {
                    result.success(PhoneNumberAuthHelper.getVersion())
                } catch (e: Throwable) {
                    result.error(CODE_FAILED, "getVersion unavailable: ${e.message}", null)
                }
            }
            else -> result.notImplemented()
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        val hadLogin = pendingLoginResult != null
        pendingCheckResult?.error(CODE_CANCELLED, "plugin detached", null)
        pendingCheckResult = null
        pendingResult?.error(CODE_CANCELLED, "plugin detached", null)
        pendingResult = null
        pendingLoginResult?.error(CODE_CANCELLED, "plugin detached", null)
        pendingLoginResult = null
        // Close any still-visible auth page so it doesn't outlive the engine.
        if (hadLogin) runCatching { helper.quitLoginPage() }
        // PhoneNumberAuthHelper is a process-wide singleton — it keeps holding
        // any listener we registered, which transitively pins the activity,
        // channel and this plugin instance in memory after detach. Null both
        // out so a fresh attach re-registers cleanly and the old plugin can be GC'd.
        runCatching { helper.setUIClickListener(null) }
        runCatching { helper.setAuthListener(null) }
    }

    private fun buildAndSetAuthUIConfig(config: Map<String, Any>) {
        val density = context.resources.displayMetrics.density
        val dialogCornerRadius = (config["cornerRadius"] as? Double ?: 16.0).toFloat() * density
        val btnCornerRadius = (config["loginBtnCornerRadius"] as? Double ?: 24.0).toFloat() * density

        val builder = AuthUIConfig.Builder()

        // ── Presentation ───────────────────────────────────────────────────────
        val dialogMode = config["dialogMode"] as? Boolean ?: true
        if (dialogMode) {
            applyAndroidDialogLayout(builder, config)
            val dragHandle = androidDialogDragHandle(config, density)
            var hasDialogBackground = false
            // maskColor has no equivalent API in the Android SDK for dialog mode.
            // backgroundColor/backgroundImageData: apply as the content-area drawable
            // (same API used in full-screen). Image wins when both are set.
            config["backgroundColor"]?.let { color ->
                runCatching {
                    builder.setPageBackgroundDrawable(
                        buildDialogColorDrawable(
                            toAndroidColor(color),
                            dialogCornerRadius,
                            dragHandle,
                        )
                    )
                    hasDialogBackground = true
                }
            }
            (config["backgroundImageData"] as? ByteArray)?.let { bytes ->
                BitmapFactory.decodeByteArray(bytes, 0, bytes.size)?.let { bmp ->
                    builder.setPageBackgroundDrawable(
                        buildBackgroundDrawable(
                            bmp,
                            config["backgroundImageContentMode"] as? String,
                            dialogCornerRadius,
                            dragHandle,
                        )
                    )
                    hasDialogBackground = true
                }
            }
            // A handle registered through addAuthRegistViewConfig is animated as a
            // separate overlay and can appear as a white bar sliding ahead of the
            // sheet. Draw it into the page background so both move as one surface.
            if (!hasDialogBackground && dragHandle != null) {
                builder.setPageBackgroundDrawable(
                    buildDialogColorDrawable(Color.WHITE, dialogCornerRadius, dragHandle)
                )
            }
        }
        // presentDirection / alertBarVisible / alertAvoidsKeyboard: iOS-only SDK features.

        // ── Status bar ────────────────────────────────────────────────────────
        builder.setStatusBarHidden(config["statusBarHidden"] as? Boolean ?: false)
        // LoginAuthActivity enters from the bottom in dialog mode. Its default
        // white status bar otherwise travels through the screen as a full-width
        // flash during that transition.
        if (dialogMode) builder.setStatusBarColor(Color.TRANSPARENT)
        // setLightColor(true) = dark icons = matches statusBarDarkText=true
        builder.setLightColor(config["statusBarDarkText"] as? Boolean ?: true)

        // ── Nav bar ───────────────────────────────────────────────────────────
        builder.setNavHidden(config["navHidden"] as? Boolean ?: true)
        config["navColor"]?.let { builder.setNavColor(toAndroidColor(it)) }
        (config["navTitle"] as? String)?.let { builder.setNavText(it) }
        config["navTitleColor"]?.let { builder.setNavTextColor(toAndroidColor(it)) }
        builder.setNavReturnHidden(config["hideBackButton"] as? Boolean ?: true)

        // ── Logo ──────────────────────────────────────────────────────────────
        builder.setLogoHidden(config["logoHidden"] as? Boolean ?: true)
        (config["logoImageData"] as? ByteArray)?.let { bytes ->
            BitmapFactory.decodeByteArray(bytes, 0, bytes.size)?.let { bmp ->
                builder.setLogoImgDrawable(BitmapDrawable(context.resources, bmp))
            }
        }

        // ── Slogan ────────────────────────────────────────────────────────────
        builder.setSloganHidden(config["sloganHidden"] as? Boolean ?: true)
        (config["sloganText"] as? String)?.let { builder.setSloganText(it) }
        config["sloganColor"]?.let { builder.setSloganTextColor(toAndroidColor(it)) }
        (config["sloganFontSize"] as? Double)?.let { builder.setSloganTextSizeDp(it.roundToInt()) }

        // ── Phone number ──────────────────────────────────────────────────────
        config["numberColor"]?.let { builder.setNumberColor(toAndroidColor(it)) }
        (config["numberFontSize"] as? Double)?.let { builder.setNumberSizeDp(it.roundToInt()) }

        // ── Login button ──────────────────────────────────────────────────────
        val btnText = config["loginBtnText"] as? String ?: "本机号码一键登录"
        builder.setLogBtnText(btnText)
        val showLoading = config["showLoginLoading"] as? Boolean ?: true
        builder.setHiddenLoading(!showLoading)
        config["loginBtnTextColor"]?.let { builder.setLogBtnTextColor(toAndroidColor(it)) }
        (config["loginBtnFontSize"] as? Double)?.let { builder.setLogBtnTextSizeDp(it.roundToInt()) }
        config["loginBtnBgColor"]?.let {
            val drawable = GradientDrawable().apply {
                setColor(toAndroidColor(it))
                this.cornerRadius = btnCornerRadius
            }
            builder.setLogBtnBackgroundDrawable(drawable)
        }

        // ── Switch button ─────────────────────────────────────────────────────
        builder.setSwitchAccHidden(config["switchBtnHidden"] as? Boolean ?: false)
        (config["switchBtnText"] as? String)?.let { builder.setSwitchAccText(it) }
        config["switchBtnColor"]?.let { builder.setSwitchAccTextColor(toAndroidColor(it)) }

        // ── Checkbox ──────────────────────────────────────────────────────────
        builder.setPrivacyState(config["checkBoxChecked"] as? Boolean ?: false)
        builder.setCheckboxHidden(config["checkBoxHidden"] as? Boolean ?: false)
        val cbSizeDp = (config["checkBoxSize"] as? Double ?: 20.0).roundToInt()
        builder.setCheckBoxWidth(cbSizeDp).setCheckBoxHeight(cbSizeDp)
        val cbFillColor      = config["checkBoxColor"]?.let { toAndroidColor(it) } ?: Color.parseColor("#1677FF")
        val cbCheckColor     = config["checkBoxCheckColor"]?.let { toAndroidColor(it) } ?: Color.WHITE
        val cbCircle         = config["checkBoxCircle"] as? Boolean ?: false
        val cbSizePx         = (cbSizeDp * density).roundToInt().coerceAtLeast(1)
        val cbInnerPaddingPx = ((config["checkBoxInnerPadding"] as? Double ?: 3.0) * density).toFloat()
        builder.setCheckedImgDrawable(
            buildCheckboxDrawable(checked = true,  fillColor = cbFillColor, checkColor = cbCheckColor,
                                  circle = cbCircle, sizePx = cbSizePx, innerPaddingPx = cbInnerPaddingPx)
        )
        builder.setUncheckedImgDrawable(
            buildCheckboxDrawable(checked = false, fillColor = cbFillColor, checkColor = cbCheckColor,
                                  circle = cbCircle, sizePx = cbSizePx, innerPaddingPx = cbInnerPaddingPx)
        )
        // checkBoxVerticalCenter: iOS-only SDK feature (no equivalent Android API).
        // expandAuthPageCheckedScope(Boolean) — always call so false resets a prior true.
        runCatching { helper.expandAuthPageCheckedScope(config["expandCheckboxTapScope"] as? Boolean ?: false) }

        // ── Privacy protocols ─────────────────────────────────────────────────
        (config["privacyOne"] as? List<*>)?.let {
            if (it.size >= 2) builder.setAppPrivacyOne(it[0].toString(), it[1].toString())
        }
        (config["privacyTwo"] as? List<*>)?.let {
            if (it.size >= 2) builder.setAppPrivacyTwo(it[0].toString(), it[1].toString())
        }
        (config["privacyThree"] as? List<*>)?.let {
            if (it.size >= 2) runCatching { builder.setAppPrivacyThree(it[0].toString(), it[1].toString()) }
        }

        // Apply only when the user explicitly sets at least one color; avoids
        // overriding the SDK's built-in defaults when neither is specified.
        val privacyBase = config["privacyColor"]?.let { toAndroidColor(it) }
        val privacyLink = config["privacyLinkColor"]?.let { toAndroidColor(it) }
        if (privacyBase != null || privacyLink != null) {
            builder.setAppPrivacyColor(
                privacyBase ?: Color.GRAY,
                privacyLink ?: Color.parseColor("#1677FF"),
            )
        }

        // Per-protocol link color overrides
        config["privacyOperatorColor"]?.let { builder.setPrivacyOperatorColor(toAndroidColor(it)) }
        config["privacyOneColor"]?.let   { builder.setPrivacyOneColor(toAndroidColor(it)) }
        config["privacyTwoColor"]?.let   { builder.setPrivacyTwoColor(toAndroidColor(it)) }
        config["privacyThreeColor"]?.let { builder.setPrivacyThreeColor(toAndroidColor(it)) }

        (config["privacyConectTexts"] as? List<*>)?.let { texts ->
            if (texts.isNotEmpty()) {
                runCatching { builder.setPrivacyConectTexts(texts.map { it.toString() }.toTypedArray()) }
            }
        }
        (config["privacyPreText"] as? String)?.let { builder.setPrivacyBefore(it) }
        (config["privacySufText"] as? String)?.let { builder.setPrivacyEnd(it) }
        (config["privacyOperatorPreText"] as? String)?.let { builder.setVendorPrivacyPrefix(it) }
        (config["privacyOperatorSufText"] as? String)?.let { builder.setVendorPrivacySuffix(it) }
        (config["privacyOperatorIndex"] as? Int)?.let { runCatching { builder.setPrivacyOperatorIndex(it) } }
        (config["privacyFontSize"] as? Double)?.let { builder.setPrivacyTextSizeDp(it.roundToInt()) }
        (config["privacyLineSpacing"] as? Double)?.let { runCatching { builder.protocolLineSpaceDp(it.roundToInt()) } }
        val centerAlign = config["privacyCenterAlign"] as? Boolean ?: true
        builder.setProtocolGravity(if (centerAlign) Gravity.CENTER else Gravity.START)
        runCatching { builder.protocolNameUseUnderLine(config["privacyOperatorUnderline"] as? Boolean ?: false) }

        // ── Protocol WebView (privacy nav) ────────────────────────────────────
        config["privacyNavColor"]?.let { builder.setWebNavColor(toAndroidColor(it)) }
        config["privacyNavTitleColor"]?.let { builder.setWebNavTextColor(toAndroidColor(it)) }
        config["privacyNavBackColor"]?.let {
            builder.setWebNavReturnImgDrawable(buildBackArrowDrawable(toAndroidColor(it)))
        }

        // ── Background image (full-screen mode) ───────────────────────────────
        if (!dialogMode) {
            config["backgroundColor"]?.let { color ->
                runCatching {
                    builder.setPageBackgroundDrawable(
                        ColorDrawable(toAndroidColor(color))
                    )
                }
            }
            (config["backgroundImageData"] as? ByteArray)?.let { bytes ->
                BitmapFactory.decodeByteArray(bytes, 0, bytes.size)?.let { bmp ->
                    builder.setPageBackgroundDrawable(
                        buildBackgroundDrawable(bmp, config["backgroundImageContentMode"] as? String)
                    )
                }
            }
        }
        // alertBarVisible / alertAvoidsKeyboard / presentDirection are iOS-only.
        // Android has no protocol-container-height API, so privacyAreaHeight remains iOS-only;
        // privacyBottomOffset and privacyHorizontalPadding still place the Android protocol view.

        // ── Advanced behavior ─────────────────────────────────────────────────
        // suspendDisMissVC and setUIClickListener are handled in registerUIClickListener()
        // (called unconditionally from the getMobileToken handler) so that callbacks
        // fire even when uiConfig is null.

        helper.setAuthUIConfig(builder.create())
    }

    private fun registerUIClickListener() {
        val request = pendingLoginResult ?: return
        helper.setUIClickListener(AuthUIControlClickListener { code, _, jsonString ->
            when (code) {
                ResultCode.CODE_ERROR_USER_LOGIN_BTN -> {
                    try {
                        val obj = org.json.JSONObject(jsonString ?: "{}")
                        val isChecked = obj.optBoolean("isChecked", false)
                        onMain {
                            if (pendingLoginResult !== request) return@onMain
                            channel.invokeMethod("onLoginButtonTap",
                                mapOf("isChecked" to isChecked))
                        }
                    } catch (_: Exception) { /* ignore parse errors */ }
                }
                ResultCode.CODE_ERROR_USER_CHECKBOX -> {
                    // SDK delivers the new checkbox state in the JSON payload
                    // (key "isChecked"), same convention as CODE_ERROR_USER_LOGIN_BTN.
                    try {
                        val obj = org.json.JSONObject(jsonString ?: "{}")
                        val isChecked = obj.optBoolean("isChecked", false)
                        onMain {
                            if (pendingLoginResult !== request) return@onMain
                            channel.invokeMethod("onCheckboxToggle",
                                mapOf("isChecked" to isChecked))
                        }
                    } catch (_: Exception) { /* ignore parse errors */ }
                }
                ResultCode.CODE_ERROR_USER_PROTOCOL_CONTROL -> {
                    if (privacyVCIsCustomized) {
                        try {
                            val obj  = org.json.JSONObject(jsonString ?: "{}")
                            val url  = obj.optString("url")
                            val name = obj.optString("name")
                            onMain {
                                if (pendingLoginResult !== request) return@onMain
                                channel.invokeMethod("onPrivacyLinkTap",
                                    mapOf("url" to url, "name" to name))
                            }
                        } catch (_: Exception) { /* ignore parse errors */ }
                    }
                }
                ResultCode.CODE_ERROR_USER_CANCEL,
                ResultCode.CODE_ERROR_USER_SWITCH -> {
                    finishUserExit(request, code, userExitMessage(code)!!)
                }
                ResultCode.CODE_ERROR_USER_CONTROL_CANCEL_BYBTN,
                ResultCode.CODE_ERROR_USER_CONTROL_CANCEL_BYKEY -> {
                    if (suspendDisMissVC) {
                        onMain {
                            if (pendingLoginResult !== request) return@onMain
                            channel.invokeMethod("onSuspendedDismiss", null)
                        }
                    }
                }
            }
        })
    }

    private fun finishUserExit(result: Result, code: String, message: String) {
        onMain {
            if (pendingLoginResult !== result) return@onMain
            pendingLoginResult = null
            // Mask/back dismissal can finish LoginAuthActivity without resetting the
            // helper's internal auth-page flag. Explicitly quit so a later login opens
            // a fresh page instead of failing with "授权页已存在，不能再次拉起".
            runCatching { helper.quitLoginPage() }
            result.error(code, message, null)
        }
    }

    // ── Image / Drawable helpers ───────────────────────────────────────────────

    private fun buildDialogColorDrawable(
        color: Int,
        cornerRadius: Float,
        dragHandle: AndroidDialogDragHandle?,
    ): Drawable = DialogColorDrawable(color, cornerRadius, dragHandle)

    private class DialogColorDrawable(
        color: Int,
        private val topCornerRadius: Float,
        private val dragHandle: AndroidDialogDragHandle?,
    ) : Drawable() {
        private val backgroundPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            this.color = color
        }
        private val handlePaint = dragHandle?.let { handle ->
            Paint(Paint.ANTI_ALIAS_FLAG).apply { this.color = handle.color }
        }

        override fun draw(canvas: Canvas) {
            val b = bounds
            if (b.isEmpty) return
            val backgroundPath = Path().apply {
                addRoundRect(
                    RectF(b),
                    topCornerRadii(topCornerRadius),
                    Path.Direction.CW,
                )
            }
            canvas.drawPath(backgroundPath, backgroundPaint)
            if (dragHandle != null && handlePaint != null) {
                drawDialogDragHandle(canvas, b, dragHandle, handlePaint)
            }
        }

        override fun setAlpha(alpha: Int) {
            backgroundPaint.alpha = alpha
            handlePaint?.alpha = alpha
            invalidateSelf()
        }

        override fun setColorFilter(colorFilter: ColorFilter?) {
            backgroundPaint.colorFilter = colorFilter
            handlePaint?.colorFilter = colorFilter
            invalidateSelf()
        }

        @Deprecated("Deprecated in Java")
        override fun getOpacity(): Int = PixelFormat.TRANSLUCENT
    }

    private fun buildBackgroundDrawable(
        bitmap: Bitmap,
        contentMode: String?,
        topCornerRadius: Float = 0f,
        dragHandle: AndroidDialogDragHandle? = null,
    ): Drawable {
        return BackgroundBitmapDrawable(
            bitmap,
            contentMode ?: "cover",
            topCornerRadius,
            dragHandle,
        )
    }

    private class BackgroundBitmapDrawable(
        private val bitmap: Bitmap,
        private val contentMode: String,
        private val topCornerRadius: Float,
        private val dragHandle: AndroidDialogDragHandle?,
    ) : Drawable() {
        private val paint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)
        private val tilePaint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG).apply {
            shader = BitmapShader(bitmap, Shader.TileMode.REPEAT, Shader.TileMode.REPEAT)
        }
        private val handlePaint = dragHandle?.let { handle ->
            Paint(Paint.ANTI_ALIAS_FLAG).apply { color = handle.color }
        }
        private val dst = RectF()

        override fun draw(canvas: Canvas) {
            val b = bounds
            if (b.isEmpty || bitmap.width <= 0 || bitmap.height <= 0) return
            val saveCount = canvas.save()
            if (topCornerRadius > 0f) {
                val clipPath = Path().apply {
                    addRoundRect(
                        RectF(b),
                        topCornerRadii(topCornerRadius),
                        Path.Direction.CW,
                    )
                }
                canvas.clipPath(clipPath)
            } else {
                canvas.clipRect(b)
            }
            if (contentMode == "tile") {
                canvas.drawRect(b, tilePaint)
                if (dragHandle != null && handlePaint != null) {
                    drawDialogDragHandle(canvas, b, dragHandle, handlePaint)
                }
                canvas.restoreToCount(saveCount)
                return
            }
            val viewW = b.width().toFloat()
            val viewH = b.height().toFloat()
            val bmpW = bitmap.width.toFloat()
            val bmpH = bitmap.height.toFloat()

            when (contentMode) {
                "fill" -> dst.set(b)
                "center" -> {
                    val left = b.left + (viewW - bmpW) / 2f
                    val top = b.top + (viewH - bmpH) / 2f
                    dst.set(left, top, left + bmpW, top + bmpH)
                }
                "contain" -> {
                    val scale = min(viewW / bmpW, viewH / bmpH)
                    setScaledRect(b, bmpW * scale, bmpH * scale)
                }
                else -> {
                    val scale = max(viewW / bmpW, viewH / bmpH)
                    setScaledRect(b, bmpW * scale, bmpH * scale)
                }
            }
            canvas.drawBitmap(bitmap, null, dst, paint)
            if (dragHandle != null && handlePaint != null) {
                drawDialogDragHandle(canvas, b, dragHandle, handlePaint)
            }
            canvas.restoreToCount(saveCount)
        }

        private fun setScaledRect(bounds: Rect, width: Float, height: Float) {
            val left = bounds.left + (bounds.width() - width) / 2f
            val top = bounds.top + (bounds.height() - height) / 2f
            dst.set(left, top, left + width, top + height)
        }

        override fun setAlpha(alpha: Int) {
            paint.alpha = alpha
            tilePaint.alpha = alpha
            handlePaint?.alpha = alpha
            invalidateSelf()
        }

        override fun setColorFilter(colorFilter: ColorFilter?) {
            paint.colorFilter = colorFilter
            tilePaint.colorFilter = colorFilter
            handlePaint?.colorFilter = colorFilter
            invalidateSelf()
        }

        @Deprecated("Deprecated in Java")
        override fun getOpacity(): Int = PixelFormat.TRANSLUCENT
    }

    private fun buildCheckboxDrawable(
        checked: Boolean,
        fillColor: Int,
        checkColor: Int,
        circle: Boolean,
        sizePx: Int,
        innerPaddingPx: Float = 0f,
    ): BitmapDrawable {
        val bmp = Bitmap.createBitmap(sizePx, sizePx, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bmp)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        val border = sizePx * 0.06f
        val rect = RectF(border, border, sizePx - border, sizePx - border)
        val radius = if (circle) (sizePx - border * 2) / 2f else sizePx * 0.15f

        if (checked) {
            paint.style = Paint.Style.FILL
            paint.color = fillColor
            canvas.drawRoundRect(rect, radius, radius, paint)

            paint.style = Paint.Style.STROKE
            paint.color = checkColor
            paint.strokeWidth = sizePx * 0.12f
            paint.strokeCap = Paint.Cap.ROUND
            paint.strokeJoin = Paint.Join.ROUND
            val path = Path()
            val p  = innerPaddingPx.coerceAtLeast(0f)
            val ck = sizePx - p * 2
            path.moveTo(p + ck * 0.22f, p + ck * 0.50f)
            path.lineTo(p + ck * 0.42f, p + ck * 0.70f)
            path.lineTo(p + ck * 0.78f, p + ck * 0.30f)
            canvas.drawPath(path, paint)
        } else {
            paint.style = Paint.Style.FILL
            paint.color = Color.WHITE
            canvas.drawRoundRect(rect, radius, radius, paint)

            paint.style = Paint.Style.STROKE
            paint.color = Color.argb(
                128,
                Color.red(fillColor), Color.green(fillColor), Color.blue(fillColor),
            )
            paint.strokeWidth = border * 1.5f
            canvas.drawRoundRect(rect, radius, radius, paint)
        }
        return BitmapDrawable(context.resources, bmp)
    }

    private fun buildBackArrowDrawable(color: Int): BitmapDrawable {
        val density = context.resources.displayMetrics.density
        val w = (12 * density).roundToInt().coerceAtLeast(1)
        val h = (20 * density).roundToInt().coerceAtLeast(1)
        val bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bmp)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            this.color = color
            style = Paint.Style.STROKE
            strokeWidth = 2f * density
            strokeCap = Paint.Cap.ROUND
            strokeJoin = Paint.Join.ROUND
        }
        val path = Path()
        path.moveTo(w * 0.83f, h * 0.10f)
        path.lineTo(w * 0.17f, h * 0.50f)
        path.lineTo(w * 0.83f, h * 0.90f)
        canvas.drawPath(path, paint)
        return BitmapDrawable(context.resources, bmp)
    }

    // ── Color helper ──────────────────────────────────────────────────────────

    private fun toAndroidColor(value: Any): Int = when (value) {
        is Int    -> value
        is Long   -> value.toInt()
        is Double -> value.toInt()
        is Float  -> value.toInt()
        else      -> Color.TRANSPARENT
    }

    companion object {
        private fun drawDialogDragHandle(
            canvas: Canvas,
            bounds: Rect,
            dragHandle: AndroidDialogDragHandle,
            paint: Paint,
        ) {
            val left = bounds.exactCenterX() - dragHandle.widthPx / 2f
            val top = bounds.top + dragHandle.topOffsetPx.toFloat()
            val rect = RectF(
                left,
                top,
                left + dragHandle.widthPx,
                top + dragHandle.heightPx,
            )
            val radius = dragHandle.heightPx / 2f
            canvas.drawRoundRect(rect, radius, radius, paint)
        }

        private fun topCornerRadii(radius: Float) = floatArrayOf(
            radius, radius,
            radius, radius,
            0f, 0f,
            0f, 0f,
        )

        private const val CODE_INVALID_ARGS = "INVALID_ARGS"
        private const val CODE_NOT_INIT = "NOT_INITIALIZED"
        private const val CODE_BUSY = "BUSY"
        private const val CODE_FAILED = "FAILED"
        private const val CODE_CANCELLED = "CANCELLED"
        private const val CODE_NO_ACTIVITY = "NO_ACTIVITY"
    }
}

internal fun isEnvironmentAvailable(code: String?): Boolean =
    code == ResultCode.CODE_ERROR_ENV_CHECK_SUCCESS

internal fun userExitMessage(code: String): String? = when (code) {
    ResultCode.CODE_ERROR_USER_CANCEL -> ResultCode.MSG_ERROR_USER_CANCEL
    ResultCode.CODE_ERROR_USER_SWITCH -> ResultCode.MSG_ERROR_USER_SWITCH
    else -> null
}

internal data class AndroidDialogDragHandle(
    val color: Int,
    val widthPx: Int,
    val heightPx: Int,
    val topOffsetPx: Int,
)

internal fun androidDialogDragHandle(
    config: Map<String, Any>,
    density: Float,
): AndroidDialogDragHandle? {
    if (config["dragHandleVisible"] as? Boolean != true) return null
    return AndroidDialogDragHandle(
        color = (config["dragHandleColor"] as? Number)?.toLong()?.toInt() ?: -2565928,
        widthPx = (((config["dragHandleWidth"] as? Number)?.toDouble() ?: 36.0) * density)
            .roundToInt()
            .coerceAtLeast(1),
        heightPx = (((config["dragHandleHeight"] as? Number)?.toDouble() ?: 4.0) * density)
            .roundToInt()
            .coerceAtLeast(1),
        topOffsetPx = (((config["dragHandleTopOffset"] as? Number)?.toDouble() ?: 8.0) * density)
            .roundToInt()
            .coerceAtLeast(0),
    )
}

internal fun applyAndroidDialogLayout(
    builder: AuthUIConfig.Builder,
    config: Map<String, Any>,
) {
    val layout = androidDialogLayout(config)
    builder.setDialogBottom(true)
    builder.setDialogHeight(layout.dialogHeight)
    builder.setTapAuthPageMaskClosePage(layout.tapBackgroundToClose)
    layout.maskAlpha?.let { builder.setDialogAlpha(it) }
    layout.numberOffsetY?.let { builder.setNumFieldOffsetY(it) }
    layout.loginBtnOffsetY?.let { builder.setLogBtnOffsetY(it) }
    layout.loginBtnHeight?.let { builder.setLogBtnHeight(it) }
    builder.setLogBtnMarginLeftAndRight(layout.horizontalPadding)
    builder.setPrivacyMargin(layout.horizontalPadding)
    layout.privacyBottomOffset?.let { builder.setPrivacyOffsetY_B(it) }
}

internal data class AndroidDialogLayout(
    val dialogHeight: Int,
    val tapBackgroundToClose: Boolean,
    val maskAlpha: Float?,
    val numberOffsetY: Int?,
    val loginBtnOffsetY: Int?,
    val loginBtnHeight: Int?,
    val horizontalPadding: Int,
    val privacyBottomOffset: Int?,
)

internal fun androidDialogLayout(config: Map<String, Any>) = AndroidDialogLayout(
    dialogHeight = (config["dialogHeight"] as? Number ?: 300.0).toDouble().roundToInt(),
    tapBackgroundToClose = config["tapBackgroundToClose"] as? Boolean ?: true,
    maskAlpha = (config["maskAlpha"] as? Number)?.toFloat(),
    numberOffsetY = (config["numberOffsetY"] as? Number)?.toDouble()?.roundToInt(),
    loginBtnOffsetY = (config["loginBtnOffsetY"] as? Number)?.toDouble()?.roundToInt(),
    loginBtnHeight = (config["loginBtnHeight"] as? Number)?.toDouble()?.roundToInt(),
    horizontalPadding = (config["privacyHorizontalPadding"] as? Number ?: 28.0).toDouble().roundToInt(),
    privacyBottomOffset = (config["privacyBottomOffset"] as? Number)?.toDouble()?.roundToInt(),
)
