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
        
        // Read currency and exchange rate settings
        val currency = prefs.getString("flutter.app_currency", "đ") ?: "đ"
        val exchangeRate = try {
            prefs.getFloat("flutter.exchange_rate", 0.00004f).toDouble()
        } catch (e: Exception) {
            try {
                java.lang.Double.longBitsToDouble(prefs.getLong("flutter.exchange_rate", 0L))
            } catch (e2: Exception) {
                0.00004
            }
        }
        
        // Read today's total from SharedPreferences (reset to 0 if not from today)
        val todayTotalVnd = if (isDataFromToday) {
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
            0L
        }
        
        // Convert to USD if currency is $ (keep as Double for precision)
        val todayTotalUsd = todayTotalVnd * exchangeRate
        val todayTotal = if (currency == "$") todayTotalUsd.toLong() else todayTotalVnd
        
        val language = prefs.getString("flutter.app_language", "vi") ?: "vi"
        val formatted = formatCompactSplit(todayTotal, language, currency, todayTotalUsd)
        
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
                
                // Add currency prefix
                val currencyPrefix = if (currency == "$") "$" else ""
                val currencySuffix = if (currency == "đ" && formatted.suffix.isEmpty()) "đ" else ""
                
                // For K suffix (< 1M): combine on same line like "350K" or "$1.245"
                // For TR, T suffixes (>= 1M): two lines - number on top, suffix below
                val isKSuffix = formatted.suffix == "K"
                
                val builder = if (isKSuffix || formatted.suffix.isEmpty()) {
                    // Single line: combine number + suffix (e.g., "$1.245" or "350K")
                    val singleLineText = currencyPrefix + formatted.number + formatted.suffix + currencySuffix
                    ShortTextComplicationData.Builder(
                        text = PlainComplicationText.Builder(singleLineText).build(),
                        contentDescription = PlainComplicationText.Builder(contentDesc).build()
                    )
                } else {
                    // Two lines: number on top (title), suffix below (text)
                    ShortTextComplicationData.Builder(
                        text = PlainComplicationText.Builder(formatted.suffix).build(),
                        contentDescription = PlainComplicationText.Builder(contentDesc).build()
                    ).setTitle(PlainComplicationText.Builder(currencyPrefix + formatted.number).build())
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

    // Helper function to format number with comma separator (US style: 72,459)
    private fun formatWithCommas(num: Double): String {
        val intPart = num.toLong()
        if (intPart < 1000) return intPart.toString()
        val formatter = NumberFormat.getNumberInstance(Locale.US)
        formatter.maximumFractionDigits = 0
        return formatter.format(intPart)
    }
    
    // Format USD amount with commas as thousand separators and 2 decimal places (e.g., 2,294.69)
    private fun formatUsdAmount(amount: Double): String {
        val formatter = NumberFormat.getNumberInstance(Locale.US)
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.format(amount)
    }

    // Split format: returns number and suffix separately
    private fun formatCompactSplit(value: Long, language: String = "vi", currency: String = "đ", usdAmount: Double = 0.0): FormattedAmount {
        val isEn = language == "en" || currency == "$"
        val isUsd = currency == "$"
        
        // For USD, don't use K suffix for amounts under $10,000 - show exact number with decimals
        if (isUsd && value < 10_000L) {
            return FormattedAmount(formatUsdAmount(usdAmount), "")
        }
        
        return when {
            value >= 1_000_000_000_000L -> {
                val num = value / 1_000_000_000_000.0
                if (isEn) {
                    if (num >= 1000) FormattedAmount(formatWithCommas(num / 1000), "Q")
                    else if (num >= 1) FormattedAmount(formatWithCommas(num), "T")
                    else FormattedAmount(String.format("%.1f", num).replace(".0", ""), "T")
                } else {
                    val tyValue = value / 1_000_000_000.0
                    FormattedAmount(formatWithCommas(tyValue), "T")
                }
            }
            value >= 1_000_000_000L -> {
                val num = value / 1_000_000_000.0
                if (isEn) {
                    FormattedAmount(formatWithCommas(num), "B")
                } else {
                    FormattedAmount(formatWithCommas(num), "T")
                }
            }
            value >= 1_000_000L -> {
                val suffix = if (isEn) "M" else "TR"
                if (isEn) {
                    val numM = value / 1_000_000.0
                    val numStr = if (numM >= 100) formatWithCommas(numM)
                                 else String.format("%.1f", numM).replace(".0", "")
                    FormattedAmount(numStr, suffix)
                } else {
                    // Vietnamese: 72,459,000 -> 72,459TR
                    val num = value / 1_000.0
                    FormattedAmount(formatWithCommas(num), suffix)
                }
            }
            value >= 1_000L -> {
                val num = value / 1_000.0
                val numStr = if (num >= 100) formatWithCommas(num)
                             else String.format("%.1f", num).replace(".0", "")
                FormattedAmount(numStr, "K")
            }
            else -> FormattedAmount(value.toString(), "")
        }
    }
}
