package io.magicmobile.android.social

import android.content.Context
import androidx.credentials.CredentialManager
import androidx.credentials.CustomCredential
import androidx.credentials.GetCredentialRequest
import androidx.credentials.exceptions.GetCredentialCancellationException
import androidx.credentials.exceptions.GetCredentialException
import com.google.android.libraries.identity.googleid.GetSignInWithGoogleOption
import com.google.android.libraries.identity.googleid.GoogleIdTokenCredential
import java.security.MessageDigest
import java.security.SecureRandom
import java.util.Base64

/**
 * Google sign-in through Android's Credential Manager (AccountSignInCard.swift does the same on iPhone). The ID token is
 * issued to the Web client of the Google Cloud project "magicmobile"; the Android client there carries the signing
 * certificate. Client IDs are public, and the app holds no secret.
 */
object GoogleSignIn {
    const val WEB_CLIENT_ID = "917754280625-metef3mern8f53ro92guud6n1qgmu3fp.apps.googleusercontent.com"

    /** Shows Google's account sheet; returns the ID token and the raw nonce whose SHA-256 is in it. */
    suspend fun signIn(context: Context): Pair<String, String> {
        val raw = ByteArray(32).also { SecureRandom().nextBytes(it) }.let { Base64.getUrlEncoder().withoutPadding().encodeToString(it) }
        val hashed = MessageDigest.getInstance("SHA-256").digest(raw.toByteArray()).joinToString("") { "%02x".format(it) }
        val option = GetSignInWithGoogleOption.Builder(WEB_CLIENT_ID).setNonce(hashed).build()
        val result = try {
            CredentialManager.create(context).getCredential(context, GetCredentialRequest.Builder().addCredentialOption(option).build())
        } catch (cancelled: GetCredentialCancellationException) {
            throw SupabaseLite.Failure("sign_in_cancelled")
        } catch (error: GetCredentialException) {
            throw SupabaseLite.Failure("error")
        }
        val credential = result.credential
        if (credential !is CustomCredential || credential.type != GoogleIdTokenCredential.TYPE_GOOGLE_ID_TOKEN_CREDENTIAL)
            throw SupabaseLite.Failure("error")
        return GoogleIdTokenCredential.createFrom(credential.data).idToken to raw
    }
}
