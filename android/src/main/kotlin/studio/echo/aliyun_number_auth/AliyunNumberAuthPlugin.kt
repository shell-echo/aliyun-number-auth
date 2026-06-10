package studio.echo.aliyun_number_auth

import android.app.Activity
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.ColorDrawable
import android.graphics.drawable.GradientDrawable
import android.os.Handler
import android.os.Looper
import android.view.Gravity
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
class AliyunNumberAuthPlugin :
    FlutterPlugin,
    MethodCallHandler,
    ActivityAware {

    private lateinit var channel: MethodChannel
    private lateinit var context: Context
    private var activity: Activity? = null

    private var privacyVCIsCustomized = false
    private var suspendDisMissVC = false
    // @Volatile on the pending Result fields: writes happen on the main thread
    // (onMethodCall / detach), but the SDK's TokenResultListener fires on a
    // background thread and snapshots these fields before posting back to main.
    // Without @Volatile the SDK thread could observe a stale reference on first
    // read, which the snapshot+identity-check pattern in tokenListener would
    // then silently drop. JVM atomicity of reference writes guarantees no torn
    // values, and @Volatile ensures the SDK thread sees the latest write —
    // making the snapshot pattern's correctness explicit rather than implicit.
    @Volatile private var pendingCheckResult: Result? = null
    @Volatile private var pendingResult: Result? = null        // for getVerifyToken
    @Volatile private var pendingLoginResult: Result? = null   // for getMobileToken
    private var isInitialized = false
    private val mainHandler = Handler(Looper.getMainLooper())

    private val tokenListener = object : TokenResultListener {
        override fun onTokenSuccess(ret: String) {
            // Snapshot the in-flight Result references on the SDK thread BEFORE
            // hopping to main. Without this, a detach → reattach → new request
            // sequence that lands between the post and the runnable would let
            // the late runnable resolve the *new* pendingLoginResult with the
            // *old* response. Snapshotting binds the runnable to the originating
            // call's Result so it can only ever resolve the right Future.
            //
            // Then on the main thread we re-check `pendingX === xSnap` before
            // resolving — if something else already consumed the Result
            // (detach, dismissLoginPage, watchdog), the snapshot reference is
            // no longer the live pending, so we DROP the event rather than
            // call `Result` twice (which throws IllegalStateException).
            val checkSnap = pendingCheckResult
            val loginSnap = pendingLoginResult
            val tokenSnap = pendingResult
            mainHandler.post {
                when {
                    checkSnap != null && pendingCheckResult === checkSnap -> {
                        // Only treat CODE_SUCCESS as "env available". Other intermediate
                        // codes the SDK may surface through onTokenSuccess (rare, but
                        // defensive) are reported as unavailable rather than a false-positive.
                        val tokenRet = runCatching { TokenRet.fromJson(ret) }.getOrNull()
                        val available = tokenRet?.code == ResultCode.CODE_SUCCESS
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
            val checkSnap = pendingCheckResult
            val loginSnap = pendingLoginResult
            val tokenSnap = pendingResult
            mainHandler.post {
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
                    helper.checkEnvAvailable(serviceType)
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
                @Suppress("UNCHECKED_CAST")
                val uiConfig = call.argument<Map<String, Any>>("uiConfig")
                privacyVCIsCustomized = uiConfig?.get("privacyVCIsCustomized") as? Boolean ?: false
                suspendDisMissVC = uiConfig?.get("suspendDisMissVC") as? Boolean ?: false
                pendingLoginResult = result
                try {
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
        // cornerRadius (dialog) is iOS-only — the Android SDK has no API for main-dialog corner radius.
        val btnCornerRadius = (config["loginBtnCornerRadius"] as? Double ?: 24.0).toFloat() * density

        val builder = AuthUIConfig.Builder()

        // ── Presentation ───────────────────────────────────────────────────────
        val dialogMode = config["dialogMode"] as? Boolean ?: true
        if (dialogMode) {
            val dialogHeightDp = (config["dialogHeight"] as? Double ?: 300.0).roundToInt()
            builder.setDialogBottom(true)
            builder.setDialogHeight(dialogHeightDp)
            builder.setTapAuthPageMaskClosePage(config["tapBackgroundToClose"] as? Boolean ?: true)
            // maskColor / maskAlpha: no equivalent API in the Android SDK for dialog mode.
            // backgroundColor: apply as the content-area drawable (same API used in full-screen).
            config["backgroundColor"]?.let { color ->
                runCatching {
                    builder.setPageBackgroundDrawable(
                        ColorDrawable(toAndroidColor(color))
                    )
                }
            }
        }
        // presentDirection / alertBarVisible / alertAvoidsKeyboard: iOS-only SDK features.

        // ── Status bar ────────────────────────────────────────────────────────
        builder.setStatusBarHidden(config["statusBarHidden"] as? Boolean ?: false)
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

        // ── Background image (full-screen mode only) ──────────────────────────
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
                    builder.setPageBackgroundDrawable(BitmapDrawable(context.resources, bmp))
                }
            }
        }
        // alertBarVisible / alertAvoidsKeyboard / presentDirection:
        // numberOffsetY / loginBtnOffsetY / loginBtnHeight / privacyAreaHeight: iOS-only SDK features.

        // ── Advanced behavior ─────────────────────────────────────────────────
        // suspendDisMissVC and setUIClickListener are handled in registerUIClickListener()
        // (called unconditionally from the getMobileToken handler) so that callbacks
        // fire even when uiConfig is null.

        helper.setAuthUIConfig(builder.create())
    }

    private fun registerUIClickListener() {
        helper.setUIClickListener(AuthUIControlClickListener { code, _, jsonString ->
            when (code) {
                ResultCode.CODE_ERROR_USER_LOGIN_BTN -> {
                    try {
                        val obj = org.json.JSONObject(jsonString ?: "{}")
                        val isChecked = obj.optBoolean("isChecked", false)
                        mainHandler.post {
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
                        mainHandler.post {
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
                            mainHandler.post {
                                channel.invokeMethod("onPrivacyLinkTap",
                                    mapOf("url" to url, "name" to name))
                            }
                        } catch (_: Exception) { /* ignore parse errors */ }
                    }
                }
                ResultCode.CODE_ERROR_USER_CONTROL_CANCEL_BYBTN,
                ResultCode.CODE_ERROR_USER_CONTROL_CANCEL_BYKEY -> {
                    if (suspendDisMissVC) {
                        mainHandler.post {
                            channel.invokeMethod("onSuspendedDismiss", null)
                        }
                    }
                }
            }
        })
    }

    // ── Image / Drawable helpers ───────────────────────────────────────────────

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
        private const val CODE_INVALID_ARGS = "INVALID_ARGS"
        private const val CODE_NOT_INIT = "NOT_INITIALIZED"
        private const val CODE_BUSY = "BUSY"
        private const val CODE_FAILED = "FAILED"
        private const val CODE_CANCELLED = "CANCELLED"
        private const val CODE_NO_ACTIVITY = "NO_ACTIVITY"
    }
}
