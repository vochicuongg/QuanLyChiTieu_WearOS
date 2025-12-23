package com.chiscung.quanlychitieu

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.drawable.Icon
import androidx.wear.watchface.complications.data.ComplicationData
import androidx.wear.watchface.complications.data.ComplicationType
import androidx.wear.watchface.complications.data.PlainComplicationText
import androidx.wear.watchface.complications.data.ShortTextComplicationData
import androidx.wear.watchface.complications.data.MonochromaticImage
import androidx.wear.watchface.complications.datasource.ComplicationRequest
import androidx.wear.watchface.complications.datasource.SuspendingComplicationDataSourceService
import java.text.NumberFormat
import java.util.Locale

private const val PREFS_NAME = "FlutterSharedPreferences"

class VFinanceComplicationService : SuspendingComplicationDataSourceService() {

    // Data class to hold split number and suffix
    data class FormattedAmount(val number: String, val suffix: String)

    override fun getPreviewData(type: ComplicationType): ComplicationData? {
        return when (type) {
            ComplicationType.SHORT_TEXT -> {
                ShortTextComplicationData.Builder(
                    text = PlainComplicationText.Builder("350K").build(),
                    contentDescription = PlainComplicationText.Builder("Chi tiêu hôm nay").build()
                )
                .setMonochromaticImage(
                    MonochromaticImage.Builder(
                        Icon.createWithResource(this, R.drawable.ic_complication)
                    ).build()
                )
                .build()
            }
            else -> null
        }
    }

    override suspend fun onComplicationRequest(request: ComplicationRequest): ComplicationData? {
        val prefs = applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        
        // Check if saved data is from today
        val savedDate = prefs.getString("flutter.tile_data_date", "") ?: ""
        val todayDate = java.text.SimpleDateFormat("dd/MM/yyyy", java.util.Locale.getDefault()).format(java.util.Date())
        val isDataFromToday = savedDate == todayDate
        
        // Read today's total from SharedPreferences (reset to 0 if not from today)
        val todayTotal = if (isDataFromToday) {
            try {
                val totalStr = prefs.getString("flutter.tile_today_total", "0") ?: "0"
                totalStr.toLongOrNull() ?: 0L
            } catch (e: Exception) {
                try { 
                    prefs.getFloat("flutter.tile_today_total", 0f).toLong()
                } catch (e2: Exception) {
                    try { prefs.getLong("flutter.tile_today_total", 0L) } catch (e3: Exception) { 0L }
                }
            }
        } else {
            0L // Reset to 0 if data is not from today
        }
        
        val language = prefs.getString("flutter.app_language", "vi") ?: "vi"
        val formatted = formatCompactSplit(todayTotal, language)
        
        // Create tap action to open the app
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return when (request.complicationType) {
            ComplicationType.SHORT_TEXT -> {
                val contentDesc = if (language == "vi") "Chi tiêu hôm nay" else "Today's spending"
                
                // For K suffix (< 1M): combine on same line like "350K"
                // For TR, T suffixes (>= 1M): two lines - number on top, suffix below
                val isKSuffix = formatted.suffix == "K"
                
                val builder = if (isKSuffix || formatted.suffix.isEmpty()) {
                    // Single line: combine number + suffix (e.g., "350K" or just the number)
                    val singleLineText = formatted.number + formatted.suffix
                    ShortTextComplicationData.Builder(
                        text = PlainComplicationText.Builder(singleLineText).build(),
                        contentDescription = PlainComplicationText.Builder(contentDesc).build()
                    )
                } else {
                    // Two lines: number on top (title), suffix below (text)
                    ShortTextComplicationData.Builder(
                        text = PlainComplicationText.Builder(formatted.suffix).build(),
                        contentDescription = PlainComplicationText.Builder(contentDesc).build()
                    ).setTitle(PlainComplicationText.Builder(formatted.number).build())
                }
                
                builder.setMonochromaticImage(
                    MonochromaticImage.Builder(
                        Icon.createWithResource(this, R.drawable.ic_complication)
                    ).build()
                )
                .setTapAction(pendingIntent)
                .build()
            }
            else -> null
        }
    }

    // Helper function to format number with dot separator
    private fun formatWithDots(num: Double): String {
        val intPart = num.toLong()
        if (intPart < 1000) return intPart.toString()
        val formatter = NumberFormat.getNumberInstance(Locale("vi", "VN"))
        return formatter.format(intPart).replace(",", ".")
    }

    // Split format: returns number and suffix separately
    private fun formatCompactSplit(value: Long, language: String = "vi"): FormattedAmount {
        val isEn = language == "en"
        return when {
            value >= 1_000_000_000_000L -> {
                val num = value / 1_000_000_000_000.0
                if (isEn) {
                    if (num >= 1000) FormattedAmount(formatWithDots(num / 1000), "Q")
                    else if (num >= 1) FormattedAmount(formatWithDots(num), "T")
                    else FormattedAmount(String.format("%.1f", num).replace(".0", ""), "T")
                } else {
                    val tyValue = value / 1_000_000_000.0
                    FormattedAmount(formatWithDots(tyValue), "T")
                }
            }
            value >= 1_000_000_000L -> {
                val num = value / 1_000_000_000.0
                if (isEn) {
                    FormattedAmount(formatWithDots(num), "B")
                } else {
                    FormattedAmount(formatWithDots(num), "T")
                }
            }
            value >= 1_000_000L -> {
                val num = value / 1_000_000.0
                val suffix = if (isEn) "M" else "TR"
                val numStr = if (num >= 100) formatWithDots(num)
                             else String.format("%.1f", num).replace(".0", "")
                FormattedAmount(numStr, suffix)
            }
            value >= 1_000L -> {
                val num = value / 1_000.0
                val numStr = if (num >= 100) formatWithDots(num)
                             else String.format("%.1f", num).replace(".0", "")
                FormattedAmount(numStr, "K")
            }
            else -> FormattedAmount(value.toString(), "")
        }
    }
}
