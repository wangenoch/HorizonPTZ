package com.horizon.horizonptz.ui

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.util.AttributeSet
import android.view.MotionEvent
import android.view.View
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.sqrt

class VirtualJoystickView @JvmOverloads constructor(
    context: Context, attrs: AttributeSet? = null, defStyleAttr: Int = 0
) : View(context, attrs, defStyleAttr) {

    private val basePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.LTGRAY
        alpha = 100
        style = Paint.Style.FILL
    }

    private val handlePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.DKGRAY
        alpha = 180
        style = Paint.Style.FILL
    }

    private var centerX = 0f
    private var centerY = 0f
    private var baseRadius = 0f
    private var handleRadius = 0f

    private var handleX = 0f
    private var handleY = 0f

    var onMoveListener: ((x: Float, y: Float) -> Unit)? = null

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        centerX = w / 2f
        centerY = h / 2f
        baseRadius = min(w, h) / 3f
        handleRadius = baseRadius / 2.5f
        handleX = centerX
        handleY = centerY
    }

    override fun onDraw(canvas: Canvas) {
        // Draw base
        canvas.drawCircle(centerX, centerY, baseRadius, basePaint)
        // Draw handle
        canvas.drawCircle(handleX, handleY, handleRadius, handlePaint)
    }

    override fun onTouchEvent(event: MotionEvent): Boolean {
        when (event.action) {
            MotionEvent.ACTION_DOWN, MotionEvent.ACTION_MOVE -> {
                updateHandlePosition(event.x, event.y)
                if (event.action == MotionEvent.ACTION_DOWN) {
                    performClick()
                }
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                resetHandle()
            }
        }
        return true
    }

    override fun performClick(): Boolean {
        super.performClick()
        return true
    }

    fun updateHandleFromExternal(xPercent: Float, yPercent: Float) {
        handleX = centerX + (xPercent * baseRadius)
        handleY = centerY + (yPercent * baseRadius)
        invalidate()
    }

    private fun updateHandlePosition(touchX: Float, touchY: Float) {
        val dx = touchX - centerX
        val dy = touchY - centerY
        val distance = sqrt(dx.pow(2) + dy.pow(2))

        if (distance <= baseRadius) {
            handleX = touchX
            handleY = touchY
        } else {
            val ratio = baseRadius / distance
            handleX = centerX + dx * ratio
            handleY = centerY + dy * ratio
        }

        // Calculate normalized values (-1.0 to 1.0)
        val normalizedX = (handleX - centerX) / baseRadius
        val normalizedY = (handleY - centerY) / baseRadius
        
        onMoveListener?.invoke(normalizedX, normalizedY)
        invalidate()
    }

    private fun resetHandle() {
        handleX = centerX
        handleY = centerY
        onMoveListener?.invoke(0f, 0f)
        invalidate()
    }
}
