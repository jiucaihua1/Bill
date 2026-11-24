package com.xiaohe.ledger

import android.content.Context
import android.text.SpannableString
import android.text.Spanned
import android.text.style.RelativeSizeSpan
import android.view.Gravity
import android.widget.RemoteViews
import androidx.compose.ui.graphics.toArgb
import es.antonborri.home_widget.HomeWidgetLaunchIntent

/** Native TextView auto-size inside the Glance composition; no parallel provider.
 * The shared Glance surface supplies the background and outline. */
object QuickWidgetContent {
    fun views(context: Context, data: WidgetDisplay, widgetId: Int? = null): RemoteViews {
        val localized = VeriFinWidgetStore.localized(context, VeriFinWidgetStore.prefs(context))
        val typography = data.typography
        val selectedColor = typography.textColor(context)
        val labelColor = selectedColor ?: if (data.dark) widgetMutedDark else widgetMutedLight
        val amountColor = selectedColor ?: if (data.dark) widgetTextDark else widgetTextLight
        val gravity = Gravity.CENTER_VERTICAL or if (typography.centered) Gravity.CENTER_HORIZONTAL else Gravity.START
        return RemoteViews(context.packageName, R.layout.quick_widget_content).apply {
            setTextViewText(R.id.quick_widget_label, scaledText(data.label, typography.scale))
            setTextViewText(R.id.quick_widget_amount, scaledText(data.amount, typography.scale))
            setTextColor(R.id.quick_widget_label, labelColor.toArgb())
            setTextColor(R.id.quick_widget_amount, amountColor.toArgb())
            setInt(R.id.quick_widget_label, "setGravity", gravity)
            setInt(R.id.quick_widget_amount, "setGravity", gravity)
            setContentDescription(R.id.quick_widget_add, localized.getString(R.string.quick_entry_button))
            if (widgetId != null) {
                val open = HomeWidgetLaunchIntent.getActivity(
                    context, MainActivity::class.java, widgetUri(widgetId, data.tapRoute, data.bookId),
                )
                val entry = HomeWidgetLaunchIntent.getActivity(
                    context, MainActivity::class.java, widgetUri(widgetId, "entry", data.bookId),
                )
                // Explicit siblings: no inherited Glance click target can turn
                // the whole weighted data column into the add button.
                listOf(R.id.quick_widget_card, R.id.quick_widget_data, R.id.quick_widget_label, R.id.quick_widget_amount)
                    .forEach { setOnClickPendingIntent(it, open) }
                setOnClickPendingIntent(R.id.quick_widget_add, entry)
            }
        }
    }

    /** Keep TextView's auto-sizing so long amounts still fit the available width. */
    private fun scaledText(text: String, scale: Float): CharSequence =
        if (scale == 1f || text.isEmpty()) text
        else SpannableString(text).apply {
            setSpan(RelativeSizeSpan(scale), 0, length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
        }
}
