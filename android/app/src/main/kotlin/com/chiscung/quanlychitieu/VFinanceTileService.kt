package com.chiscung.quanlychitieu

import android.content.Context
import androidx.wear.protolayout.ActionBuilders
import androidx.wear.protolayout.ColorBuilders.argb
import androidx.wear.protolayout.DimensionBuilders.dp
import androidx.wear.protolayout.DimensionBuilders.sp
import androidx.wear.protolayout.LayoutElementBuilders
import androidx.wear.protolayout.ModifiersBuilders
import androidx.wear.protolayout.ResourceBuilders
import androidx.wear.protolayout.TimelineBuilders
import androidx.wear.tiles.RequestBuilders
import androidx.wear.tiles.TileBuilders
import androidx.wear.tiles.TileService
import com.google.common.util.concurrent.Futures
import com.google.common.util.concurrent.ListenableFuture
import org.json.JSONArray
import java.text.NumberFormat
import java.util.Locale

private const val RESOURCES_VERSION = "1"
private const val PREFS_NAME = "FlutterSharedPreferences"

class VFinanceTileService : TileService() {

    override fun onTileRequest(requestParams: RequestBuilders.TileRequest): ListenableFuture<TileBuilders.Tile> {
        val prefs = applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        
        // Check if saved data is from today
        val savedDate = prefs.getString("flutter.tile_data_date", "") ?: ""
        val todayDate = java.text.SimpleDateFormat("dd/MM/yyyy", java.util.Locale.getDefault()).format(java.util.Date())
        val isDataFromToday = savedDate == todayDate
        
        // Read currency and exchange rate settings
        val currency = prefs.getString("flutter.app_currency", "đ") ?: "đ"
        val exchangeRate = try {
            // Try to read as Float first (might be stored as Float)
            prefs.getFloat("flutter.exchange_rate", 0.00004f).toDouble()
        } catch (e: Exception) {
            try {
                // Try reading as Long (stored as raw bits)
                java.lang.Double.longBitsToDouble(prefs.getLong("flutter.exchange_rate", 0L))
            } catch (e2: Exception) {
                0.00004 // Default fallback
            }
        }
        
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
        
        // Convert to USD if currency is $ (keep Double for precision)
        val todayTotalUsd = todayTotalVnd * exchangeRate
        val todayTotal = if (currency == "$") todayTotalUsd.toLong() else todayTotalVnd
        
        val language = prefs.getString("flutter.app_language", "vi") ?: "vi"
        val topExpensesJson = if (isDataFromToday) {
            prefs.getString("flutter.tile_top_expenses", "[]") ?: "[]"
        } else {
            "[]"
        }
        
        // Parse top 2 expenses  
        var expense1Name = ""
        var expense1Amt = ""
        var expense2Name = ""
        var expense2Amt = ""
        
        try {
            val jsonArray = JSONArray(topExpensesJson)
            if (jsonArray.length() >= 1) {
                val obj1 = jsonArray.getJSONObject(0)
                val cat1 = obj1.optString("category", "khac")
                val amt1Vnd = obj1.optLong("amount", 0L)
                val amt1Usd = amt1Vnd * exchangeRate
                val amt1 = if (currency == "$") amt1Usd.toLong() else amt1Vnd
                val catName1 = if (language == "en") getCategoryNameEn(cat1) else obj1.optString("categoryVi", "Khác")
                expense1Name = getCategoryIcon(cat1) + " " + truncateName(catName1)
                expense1Amt = formatCompact(amt1, language, currency, amt1Usd)
            }
            if (jsonArray.length() >= 2) {
                val obj2 = jsonArray.getJSONObject(1)
                val cat2 = obj2.optString("category", "khac")
                val amt2Vnd = obj2.optLong("amount", 0L)
                val amt2Usd = amt2Vnd * exchangeRate
                val amt2 = if (currency == "$") amt2Usd.toLong() else amt2Vnd
                val catName2 = if (language == "en") getCategoryNameEn(cat2) else obj2.optString("categoryVi", "Khác")
                expense2Name = getCategoryIcon(cat2) + " " + truncateName(catName2)
                expense2Amt = formatCompact(amt2, language, currency, amt2Usd)
            }
        } catch (e: Exception) { }
        
        val formattedAmount = formatCompact(todayTotal, language, currency, todayTotalUsd)
        val currencySymbol = if (currency == "$") "$" else "đ"
        val titleText = if (language == "vi") "Tổng chi tiêu hôm nay" else "Total spending today"
        val topLabel = if (language == "vi") "Chi tiêu lớn nhất" else "Top spending"
        
        val tile = TileBuilders.Tile.Builder()
            .setResourcesVersion(RESOURCES_VERSION)
            .setFreshnessIntervalMillis(15000)
            .setTileTimeline(
                TimelineBuilders.Timeline.Builder()
                    .addTimelineEntry(
                        TimelineBuilders.TimelineEntry.Builder()
                            .setLayout(
                                LayoutElementBuilders.Layout.Builder()
                                    .setRoot(createTileLayout(
                                        titleText, formattedAmount, topLabel,
                                        expense1Name, expense1Amt,
                                        expense2Name, expense2Amt,
                                        currencySymbol
                                    ))
                                    .build()
                            )
                            .build()
                    )
                    .build()
            )
            .build()

        return Futures.immediateFuture(tile)
    }

    override fun onTileResourcesRequest(requestParams: RequestBuilders.ResourcesRequest): ListenableFuture<ResourceBuilders.Resources> {
        return Futures.immediateFuture(
            ResourceBuilders.Resources.Builder()
                .setVersion(RESOURCES_VERSION)
                .build()
        )
    }

    private fun getCategoryIcon(category: String): String {
        return when (category) {
            "nhaTro" -> "🏠"
            "hocPhi" -> "🎓"
            "thucAn" -> "🍜"
            "doUong" -> "☕"
            "xang" -> "⛽"
            "muaSam" -> "🛍️"
            "suaXe" -> "🔧"
            else -> "💰"
        }
    }
    
    private fun getCategoryNameEn(category: String): String {
        return when (category) {
            "nhaTro" -> "Rent"
            "hocPhi" -> "Tuition"
            "thucAn" -> "Food"
            "doUong" -> "Drinks"
            "xang" -> "Gas"
            "muaSam" -> "Shopping"
            "suaXe" -> "Repair"
            else -> "Other"
        }
    }
    
    private fun truncateName(name: String): String {
        return if (name.length > 8) name.substring(0, 8) + ".." else name
    }

    private fun createTileLayout(
        title: String, 
        amount: String,
        topLabel: String,
        exp1Name: String,
        exp1Amt: String,
        exp2Name: String,
        exp2Amt: String,
        currencySymbol: String = "đ"
    ): LayoutElementBuilders.LayoutElement {
        val clickable = ModifiersBuilders.Clickable.Builder()
    .setId("open_app")
    .setOnClick(
        ActionBuilders.LaunchAction.Builder()
            .setAndroidActivity(
                ActionBuilders.AndroidActivity.Builder()
                    .setPackageName(packageName)
                    .setClassName("$packageName.MainActivity")
                    .build()
            )
            .build()
    )
    .build()

    val textElement = LayoutElementBuilders.Text.Builder()
    .setText("Mở ứng dụng") // Thay đổi nội dung text tùy ý
    .setFontStyle(
        LayoutElementBuilders.FontStyle.Builder()
            .setWeight(LayoutElementBuilders.FONT_WEIGHT_BOLD) // ĐÂY LÀ NƠI CHỈNH ĐẬM ĐÚNG
            .build()
    )
    .setModifiers(
        ModifiersBuilders.Modifiers.Builder()
            .setClickable(clickable) // Gán sự kiện click vào đây
            .build()
    )
    .build()

        val modifiers = ModifiersBuilders.Modifiers.Builder()
            .setClickable(clickable)
            .build()

        val columnBuilder = LayoutElementBuilders.Column.Builder()
            .setWidth(dp(210f))
            .setHeight(dp(210f))
            .setHorizontalAlignment(LayoutElementBuilders.HORIZONTAL_ALIGN_CENTER)
            .setModifiers(
                ModifiersBuilders.Modifiers.Builder()
                    .setPadding(
                        ModifiersBuilders.Padding.Builder()
                            .setTop(dp(28f))
                            .setStart(dp(12f))
                            .setEnd(dp(12f))
                            .build()
                    )
                    .build()
            )
            .addContent(
                LayoutElementBuilders.Text.Builder()
                    .setText("VFinance")
                    .setFontStyle(
                        LayoutElementBuilders.FontStyle.Builder()
                            .setSize(sp(16f))
                            .setColor(argb(0xFF4CAF93.toInt()))
                            .setWeight(LayoutElementBuilders.FONT_WEIGHT_BOLD)
                            .build()
                    )
                    .build()
            )
            .addContent(LayoutElementBuilders.Spacer.Builder().setHeight(dp(2f)).build())
            .addContent(
                LayoutElementBuilders.Text.Builder()
                    .setText(title)
                    .setFontStyle(
                        LayoutElementBuilders.FontStyle.Builder()
                            .setSize(sp(11f))
                            .setColor(argb(0xB3FFFFFF.toInt()))
                            .build()
                    )
                    .build()
            )
            .addContent(LayoutElementBuilders.Spacer.Builder().setHeight(dp(2f)).build())
            .addContent(
                LayoutElementBuilders.Text.Builder()
                    .setText(if (currencySymbol == "$") "$" + amount else amount + " đ")
                    .setFontStyle(
                        LayoutElementBuilders.FontStyle.Builder()
                            .setSize(sp(24f))
                            .setColor(argb(0xFFF08080.toInt()))
                            .setWeight(LayoutElementBuilders.FONT_WEIGHT_BOLD)
                            .build()
                    )
                    .build()
            )

        // Add top expenses in separate boxes
        if (exp1Name.isNotEmpty() || exp2Name.isNotEmpty()) {
            columnBuilder.addContent(LayoutElementBuilders.Spacer.Builder().setHeight(dp(10f)).build())
            
            // Row for expense boxes
            val rowBuilder = LayoutElementBuilders.Row.Builder()
                .setWidth(dp(190f))
                .setHeight(dp(60f))
                .setVerticalAlignment(LayoutElementBuilders.VERTICAL_ALIGN_CENTER)
            
            // First expense box
            if (exp1Name.isNotEmpty()) {
                rowBuilder.addContent(createExpenseBox(exp1Name, exp1Amt, currencySymbol))
            }
            
            // Spacer between boxes
            if (exp1Name.isNotEmpty() && exp2Name.isNotEmpty()) {
                rowBuilder.addContent(LayoutElementBuilders.Spacer.Builder().setWidth(dp(8f)).build())
            }
            
            // Second expense box
            if (exp2Name.isNotEmpty()) {
                rowBuilder.addContent(createExpenseBox(exp2Name, exp2Amt, currencySymbol))
            }
            
            columnBuilder.addContent(rowBuilder.build())
        }

        return LayoutElementBuilders.Box.Builder()
            .setWidth(dp(210f))
            .setHeight(dp(210f))
            .setHorizontalAlignment(LayoutElementBuilders.HORIZONTAL_ALIGN_CENTER)
            .setVerticalAlignment(LayoutElementBuilders.VERTICAL_ALIGN_CENTER)
            .setModifiers(modifiers)
            .addContent(columnBuilder.build())
            .build()
    }
    
    private fun createExpenseBox(name: String, amount: String, currencySymbol: String = "đ"): LayoutElementBuilders.LayoutElement {
        return LayoutElementBuilders.Box.Builder()
            .setWidth(dp(90f))
            .setHeight(dp(56f))
            .setHorizontalAlignment(LayoutElementBuilders.HORIZONTAL_ALIGN_CENTER)
            .setVerticalAlignment(LayoutElementBuilders.VERTICAL_ALIGN_CENTER)
            .setModifiers(
                ModifiersBuilders.Modifiers.Builder()
                    .setBackground(
                        ModifiersBuilders.Background.Builder()
                            .setColor(argb(0xFF2A2A2A.toInt()))
                            .setCorner(
                                ModifiersBuilders.Corner.Builder()
                                    .setRadius(dp(14f))
                                    .build()
                            )
                            .build()
                    )
                    .setPadding(
                        ModifiersBuilders.Padding.Builder()
                            .setAll(dp(6f))
                            .build()
                    )
                    .build()
            )
            .addContent(
                LayoutElementBuilders.Column.Builder()
                    .setWidth(dp(84f))
                    .setHeight(dp(48f))
                    .setHorizontalAlignment(LayoutElementBuilders.HORIZONTAL_ALIGN_CENTER)
                    .setModifiers(
                        ModifiersBuilders.Modifiers.Builder()
                            .setPadding(
                                ModifiersBuilders.Padding.Builder()
                                    .setTop(dp(6f))
                                    .build()
                            )
                            .build()
                    )
                    .addContent(
                        LayoutElementBuilders.Text.Builder()
                            .setText(name)
                            .setFontStyle(
                                LayoutElementBuilders.FontStyle.Builder()
                                    .setSize(sp(12f))
                                    .setColor(argb(0xFFFFFFFF.toInt()))
                                    .build()
                            )
                            .setMaxLines(1)
                            .build()
                    )
                    .addContent(LayoutElementBuilders.Spacer.Builder().setHeight(dp(3f)).build())
                    .addContent(
                        LayoutElementBuilders.Text.Builder()
                            .setText(if (currencySymbol == "$") "$" + amount else amount + " đ")
                            .setFontStyle(
                                LayoutElementBuilders.FontStyle.Builder()
                                    .setSize(sp(11f))
                                    .setColor(argb(0xFFF08080.toInt()))
                                    .setWeight(LayoutElementBuilders.FONT_WEIGHT_BOLD)
                                    .build()
                            )
                            .setMaxLines(1)
                            .build()
                    )
                    .build()
            )
            .build()
    }

    private fun formatNumber(value: Long): String {
        if (value == 0L) return "0"
        val formatter = NumberFormat.getNumberInstance(Locale("vi", "VN"))
        return formatter.format(value).replace(",", ".")
    }
    
    // Helper function to format number with comma separator (US style: 72,459)
    private fun formatWithCommas(num: Double): String {
        val intPart = num.toLong()
        if (intPart < 1000) return intPart.toString()
        val formatter = NumberFormat.getNumberInstance(Locale.US)
        formatter.maximumFractionDigits = 0
        return formatter.format(intPart)
    }
    
    // Format USD amount with 2 decimal places when it has cents
    private fun formatUsdAmount(amount: Double): String {
        val cents = amount - amount.toLong()
        return if (cents > 0.001) {
            String.format(Locale.US, "%.2f", amount)
        } else {
            amount.toLong().toString()
        }
    }
    
    // Compact format for expense boxes
    // Vietnamese: T (tỷ=10^9), Tr (triệu=10^6), K (nghìn=10^3)
    // English/USD: B (billion=10^9), M (million=10^6), K (thousand=10^3)
    private fun formatCompact(value: Long, language: String = "vi", currency: String = "đ", usdAmount: Double = 0.0): String {
        val isEn = language == "en" || currency == "$"
        val isUsd = currency == "$"
        
        // For USD, don't use K suffix for amounts under $10,000 - show exact number with decimals
        if (isUsd && value < 10_000L) {
            return formatUsdAmount(usdAmount)
        }
        
        return when {
            // >= 1 trillion (10^12)
            value >= 1_000_000_000_000L -> {
                val num = value / 1_000_000_000_000.0
                if (isEn) {
                    if (num >= 1000) formatWithCommas(num / 1000) + "Q"
                    else if (num >= 1) formatWithCommas(num) + "T"
                    else String.format("%.1f", num).replace(".0", "") + "T"
                } else {
                    // For VND: show as Ty (e.g., 1,234T for 1.234 trillion)
                    val tyValue = value / 1_000_000_000.0
                    formatWithCommas(tyValue) + "T"
                }
            }
            // >= 1 billion (10^9)
            value >= 1_000_000_000L -> {
                val num = value / 1_000_000_000.0
                if (isEn) {
                    formatWithCommas(num) + "B"
                } else {
                    // For VND: show as Ty (e.g., 1.5T for 1.5 billion)
                    formatWithCommas(num) + "T"
                }
            }
            // >= 1 million (10^6)
            value >= 1_000_000L -> {
                // For VND: show thousands in millions (72,459,000 -> 72,459Tr)
                val num = value / 1_000.0  // Divide by 1000 to get thousands
                val suffix = if (isEn) "M" else "Tr"
                if (isEn) {
                    val numM = value / 1_000_000.0
                    if (numM >= 100) formatWithCommas(numM) + suffix
                    else String.format("%.1f", numM).replace(".0", "") + suffix
                } else {
                    // Vietnamese: 72,459,000 -> 72,459Tr
                    formatWithCommas(num) + suffix
                }
            }
            // >= 1 thousand (10^3)
            value >= 1_000L -> {
                val num = value / 1_000.0
                if (num >= 100) formatWithCommas(num) + "K"
                else String.format("%.1f", num).replace(".0", "") + "K"
            }
            else -> value.toString()
        }
    }
}
