package com.example.quan_ly_chi_tieu

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
            prefs.getLong("flutter.tile_today_total", 0L).toInt()
        } catch (e: ClassCastException) {
            try { prefs.getInt("flutter.tile_today_total", 0) } catch (e2: Exception) { 0 }
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
                val catVi1 = obj1.optString("categoryVi", "Khac")
                val amt1 = obj1.optInt("amount", 0)
                expense1Name = getCategoryIcon(cat1) + " " + truncateName(catVi1)
                expense1Amt = formatNumber(amt1)
            }
            if (jsonArray.length() >= 2) {
                val obj2 = jsonArray.getJSONObject(1)
                val cat2 = obj2.optString("category", "khac")
                val catVi2 = obj2.optString("categoryVi", "Khac")
                val amt2 = obj2.optInt("amount", 0)
                expense2Name = getCategoryIcon(cat2) + " " + truncateName(catVi2)
                expense2Amt = formatNumber(amt2)
            }
        } catch (e: Exception) { }
        
        val formattedAmount = formatNumber(todayTotal)
        val titleText = if (language == "vi") "Tổng chi tiêu" else "Today"
        val topLabel = if (language == "vi") "Chi tiêu lớn nhất" else "Top"
        
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
                            .setClassName(packageName + ".MainActivity")
                            .build()
                    )
                    .build()
            )
            .build()

        val modifiers = ModifiersBuilders.Modifiers.Builder()
            .setClickable(clickable)
            .build()

        val columnBuilder = LayoutElementBuilders.Column.Builder()
            .setWidth(dp(180f))
            .setHeight(dp(180f))
            .setHorizontalAlignment(LayoutElementBuilders.HORIZONTAL_ALIGN_CENTER)
            .setModifiers(
                ModifiersBuilders.Modifiers.Builder()
                    .setPadding(
                        ModifiersBuilders.Padding.Builder()
                            .setTop(dp(20f))
                            .setStart(dp(10f))
                            .setEnd(dp(10f))
                            .build()
                    )
                    .build()
            )
            .addContent(
                LayoutElementBuilders.Text.Builder()
                    .setText("VFinance")
                    .setFontStyle(
                        LayoutElementBuilders.FontStyle.Builder()
                            .setSize(sp(13f))
                            .setColor(argb(0xFF4CAF93.toInt()))
                            .setWeight(LayoutElementBuilders.FONT_WEIGHT_BOLD)
                            .build()
                    )
                    .build()
            )
            .addContent(LayoutElementBuilders.Spacer.Builder().setHeight(dp(1f)).build())
            .addContent(
                LayoutElementBuilders.Text.Builder()
                    .setText(title)
                    .setFontStyle(
                        LayoutElementBuilders.FontStyle.Builder()
                            .setSize(sp(9f))
                            .setColor(argb(0xB3FFFFFF.toInt()))
                            .build()
                    )
                    .build()
            )
            .addContent(LayoutElementBuilders.Spacer.Builder().setHeight(dp(1f)).build())
            .addContent(
                LayoutElementBuilders.Text.Builder()
                    .setText(amount + " đ")
                    .setFontStyle(
                        LayoutElementBuilders.FontStyle.Builder()
                            .setSize(sp(18f))
                            .setColor(argb(0xFFF08080.toInt()))
                            .setWeight(LayoutElementBuilders.FONT_WEIGHT_BOLD)
                            .build()
                    )
                    .build()
            )

        // Add top expenses in separate boxes
        if (exp1Name.isNotEmpty() || exp2Name.isNotEmpty()) {
            columnBuilder.addContent(LayoutElementBuilders.Spacer.Builder().setHeight(dp(6f)).build())
            
            // Row for expense boxes
            val rowBuilder = LayoutElementBuilders.Row.Builder()
                .setWidth(dp(160f))
                .setHeight(dp(50f))
                .setVerticalAlignment(LayoutElementBuilders.VERTICAL_ALIGN_CENTER)
            
            // First expense box
            if (exp1Name.isNotEmpty()) {
                rowBuilder.addContent(createExpenseBox(exp1Name, exp1Amt))
            }
            
            // Spacer between boxes
            if (exp1Name.isNotEmpty() && exp2Name.isNotEmpty()) {
                rowBuilder.addContent(LayoutElementBuilders.Spacer.Builder().setWidth(dp(6f)).build())
            }
            
            // Second expense box
            if (exp2Name.isNotEmpty()) {
                rowBuilder.addContent(createExpenseBox(exp2Name, exp2Amt))
            }
            
            columnBuilder.addContent(rowBuilder.build())
        }

        return LayoutElementBuilders.Box.Builder()
            .setWidth(dp(180f))
            .setHeight(dp(180f))
            .setModifiers(modifiers)
            .addContent(columnBuilder.build())
            .build()
    }
    
    private fun createExpenseBox(name: String, amount: String): LayoutElementBuilders.LayoutElement {
        return LayoutElementBuilders.Box.Builder()
            .setWidth(dp(75f))
            .setHeight(dp(48f))
            .setHorizontalAlignment(LayoutElementBuilders.HORIZONTAL_ALIGN_CENTER)
            .setVerticalAlignment(LayoutElementBuilders.VERTICAL_ALIGN_CENTER)
            .setModifiers(
                ModifiersBuilders.Modifiers.Builder()
                    .setBackground(
                        ModifiersBuilders.Background.Builder()
                            .setColor(argb(0xFF2A2A2A.toInt()))
                            .setCorner(
                                ModifiersBuilders.Corner.Builder()
                                    .setRadius(dp(12f))
                                    .build()
                            )
                            .build()
                    )
                    .setPadding(
                        ModifiersBuilders.Padding.Builder()
                            .setAll(dp(4f))
                            .build()
                    )
                    .build()
            )
            .addContent(
                LayoutElementBuilders.Column.Builder()
                    .setWidth(dp(70f))
                    .setHeight(dp(44f))
                    .setHorizontalAlignment(LayoutElementBuilders.HORIZONTAL_ALIGN_CENTER)
                    .addContent(
                        LayoutElementBuilders.Text.Builder()
                            .setText(name)
                            .setFontStyle(
                                LayoutElementBuilders.FontStyle.Builder()
                                    .setSize(sp(10f))
                                    .setColor(argb(0xFFFFFFFF.toInt()))
                                    .build()
                            )
                            .setMaxLines(1)
                            .build()
                    )
                    .addContent(LayoutElementBuilders.Spacer.Builder().setHeight(dp(2f)).build())
                    .addContent(
                        LayoutElementBuilders.Text.Builder()
                            .setText(amount + "đ")
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

    private fun formatNumber(value: Int): String {
        if (value == 0) return "0"
        val formatter = NumberFormat.getNumberInstance(Locale("vi", "VN"))
        return formatter.format(value).replace(",", ".")
    }
}
