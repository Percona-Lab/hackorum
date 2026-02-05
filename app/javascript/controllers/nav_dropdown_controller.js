import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.onDocumentClick = this.handleDocumentClick.bind(this)
    document.addEventListener("click", this.onDocumentClick)
  }

  disconnect() {
    document.removeEventListener("click", this.onDocumentClick)
  }

  handleDocumentClick(event) {
    if (!this.element.open) return
    if (this.element.contains(event.target)) return
    this.element.removeAttribute("open")
  }
}
