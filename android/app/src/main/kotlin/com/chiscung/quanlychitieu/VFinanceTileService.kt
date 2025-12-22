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
        
        val todayTotal = try {
            // Read as String (most reliable cross-platform format)
            val totalStr = prefs.getString("flutter.tile_today_total", "0") ?: "0"
            totalStr.toLongOrNull() ?: 0L
        } catch (e: Exception) {
            // Fallback for old Float/Double values
            try { 
                prefs.getFloat("flutter.tile_today_total", 0f).toLong()
            } catch (e2: Exception) {
                try { prefs.getLong("flutter.tile_today_total", 0L) } catch (e3: Exception) { 0L }
            }
        }
        
        val language = prefs.getString("flutter.app_language", "vi") ?: "vi"
        val topExpensesJson = prefs.getString("flutter.tile_top_expenses", "[]") ?: "[]"
        
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
                val amt1 = obj1.optLong("amount", 0L)
                val catName1 = if (language == "en") getCategoryNameEn(cat1) else obj1.optString("categoryVi", "Khác")
                expense1Name = getCategoryIcon(cat1) + " " + truncateName(catName1)
                expense1Amt = formatCompact(amt1, language)
            }
            if (jsonArray.length() >= 2) {
                val obj2 = jsonArray.getJSONObject(1)
                val cat2 = obj2.optString("category", "khac")
                val amt2 = obj2.optLong("amount", 0L)
                val catName2 = if (language == "en") getCategoryNameEn(cat2) else obj2.optString("categoryVi", "Khác")
                expense2Name = getCategoryIcon(cat2) + " " + truncateName(catName2)
                expense2Amt = formatCompact(amt2, language)
            }
        } catch (e: Exception) { }
        
        val formattedAmount = formatCompact(todayTotal, language)
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
                                        expense2Name, expense2Amt
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
        exp2Amt: String
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
                    .setText(amount + " đ")
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
                rowBuilder.addContent(createExpenseBox(exp1Name, exp1Amt))
            }
            
            // Spacer between boxes
            if (exp1Name.isNotEmpty() && exp2Name.isNotEmpty()) {
                rowBuilder.addContent(LayoutElementBuilders.Spacer.Builder().setWidth(dp(8f)).build())
            }
            
            // Second expense box
            if (exp2Name.isNotEmpty()) {
                rowBuilder.addContent(createExpenseBox(exp2Name, exp2Amt))
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
    
    private fun createExpenseBox(name: String, amount: String): LayoutElementBuilders.LayoutElement {
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
                            .setText(amount + " đ")
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
    
    // Compact format for expense boxes
    // Vietnamese: T (tỷ=10^9), Tr (triệu=10^6), K (nghìn=10^3)
    // English: T (trillion=10^12), B (billion=10^9), M (million=10^6), K (thousand=10^3)
    private fun formatCompact(value: Long, language: String = "vi"): String {
        val isEn = language == "en"
        return when {
            // >= 1 trillion (10^12)
            value >= 1_000_000_000_000L -> {
                val num = value / 1_000_000_000_000.0
                if (isEn) {
                    // English: T = trillion
                    if (num >= 1000) String.format("%.0f", num / 1000) + "Q" // quadrillion
                    else if (num >= 1) String.format("%.0f", num) + "T"
                    else String.format("%.1f", num).replace(".0", "") + "T"
                } else {
                    // Vietnamese: T = tỷ (10^9), so 10^12 = nghìn tỷ
                    val tyValue = value / 1_000_000_000.0
                    String.format("%.0f", tyValue) + "T"
                }
            }
            // >= 1 billion (10^9)
            value >= 1_000_000_000L -> {
                val num = value / 1_000_000_000.0
                if (isEn) {
                    // English: B = billion
                    if (num >= 100) String.format("%.0f", num) + "B"
                    else String.format("%.0f", num) + "B"
                } else {
                    // Vietnamese: T = tỷ
                    String.format("%.0f", num) + "T"
                }
            }
            // >= 1 million (10^6)
            value >= 1_000_000L -> {
                val num = value / 1_000_000.0
                val suffix = if (isEn) "M" else "Tr"
                if (num >= 100) String.format("%.0f", num) + suffix
                else String.format("%.1f", num).replace(".0", "") + suffix
            }
            // >= 1 thousand (10^3)
            value >= 1_000L -> {
                val num = value / 1_000.0
                if (num >= 100) String.format("%.0f", num) + "K"
                else String.format("%.1f", num).replace(".0", "") + "K"
            }
            else -> value.toString()
        }
    }
}
