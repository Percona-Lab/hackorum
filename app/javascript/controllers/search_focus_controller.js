import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "section"]

  connect() {
    this._onHashChange = this.focusIfHash.bind(this)
    this._onTurboLoad = this.focusIfHash.bind(this)
    this._onLinkClick = this.handleLinkClick.bind(this)
    window.addEventListener("hashchange", this._onHashChange)
    document.addEventListener("turbo:load", this._onTurboLoad)
    document.addEventListener("click", this._onLinkClick)
    this.focusIfHash()
  }

  disconnect() {
    window.removeEventListener("hashchange", this._onHashChange)
    document.removeEventListener("turbo:load", this._onTurboLoad)
    document.removeEventListener("click", this._onLinkClick)
  }

  focusIfHash() {
    const isSearch = window.location.hash === "#search"
    if (this.hasSectionTarget) {
      this.sectionTarget.classList.toggle("is-search-focus", isSearch)
    }
    if (isSearch && this.hasInputTarget) {
      this.inputTarget.focus()
    }
  }

  handleLinkClick(event) {
    if (event.defaultPrevented) return
    const link = event.target.closest('a[href="#search"]')
    if (!link) return
    window.location.hash = "search"
    setTimeout(() => this.focusIfHash(), 0)
  }
}
