import { Controller } from "@hotwired/stimulus"

const SWIPE_DISTANCE_PX = 60
const SWIPE_AXIS_RATIO = 1.2
const SWIPE_TIME_MS = 700

export default class extends Controller {
  connect() {
    this.onPointerDown = this.onPointerDown.bind(this)
    this.onPointerMove = this.onPointerMove.bind(this)
    this.onPointerUp = this.onPointerUp.bind(this)
    window.addEventListener("pointerdown", this.onPointerDown, { passive: true })
  }

  disconnect() {
    window.removeEventListener("pointerdown", this.onPointerDown, { passive: true })
    this.detachTrackingListeners()
  }

  onPointerDown(event) {
    if (!event.isPrimary) return
    if (event.pointerType !== "touch" && event.pointerType !== "pen") return
    if (event.button && event.button !== 0) return
    if (this.shouldIgnoreTarget(event.target)) return

    this.tracking = true
    this.pointerId = event.pointerId
    this.startX = event.clientX
    this.startY = event.clientY
    this.startTime = performance.now()
    this.lastX = event.clientX
    this.lastY = event.clientY

    window.addEventListener("pointermove", this.onPointerMove, { passive: true })
    window.addEventListener("pointerup", this.onPointerUp, { passive: true })
    window.addEventListener("pointercancel", this.onPointerUp, { passive: true })
  }

  onPointerMove(event) {
    if (!this.tracking || event.pointerId !== this.pointerId) return
    this.lastX = event.clientX
    this.lastY = event.clientY
  }

  onPointerUp(event) {
    if (!this.tracking || event.pointerId !== this.pointerId) return

    const elapsed = performance.now() - this.startTime
    const deltaX = this.lastX - this.startX
    const deltaY = this.lastY - this.startY

    this.tracking = false
    this.pointerId = null
    this.detachTrackingListeners()

    if (elapsed > SWIPE_TIME_MS) return
    if (Math.abs(deltaX) < SWIPE_DISTANCE_PX) return
    if (Math.abs(deltaX) < Math.abs(deltaY) * SWIPE_AXIS_RATIO) return

    if (deltaX > 0) {
      window.history.back()
    } else {
      window.history.forward()
    }
  }

  detachTrackingListeners() {
    window.removeEventListener("pointermove", this.onPointerMove, { passive: true })
    window.removeEventListener("pointerup", this.onPointerUp, { passive: true })
    window.removeEventListener("pointercancel", this.onPointerUp, { passive: true })
  }

  shouldIgnoreTarget(target) {
    if (!target) return true
    if (target.closest("input, textarea, select, [contenteditable='true']")) return true
    if (this.isInHorizontalScrollableArea(target)) return true
    return false
  }

  isInHorizontalScrollableArea(target) {
    let el = target
    while (el && el !== document.body) {
      const style = window.getComputedStyle(el)
      const overflowX = style.overflowX
      if ((overflowX === "auto" || overflowX === "scroll" || overflowX === "overlay") &&
          el.scrollWidth > el.clientWidth + 1) {
        return true
      }
      el = el.parentElement
    }
    return false
  }
}
