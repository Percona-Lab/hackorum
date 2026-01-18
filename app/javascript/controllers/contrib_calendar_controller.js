import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

export default class extends Controller {
  static values = { filterSelector: String }

  clickDate(event) {
    event.preventDefault()

    const link = event.currentTarget
    const filterForm = document.querySelector(this.filterSelectorValue)
    const url = new URL(link.href)

    if (filterForm) {
      const checkboxes = filterForm.querySelectorAll('input[name="filters[]"]:checked')
      checkboxes.forEach(checkbox => {
        url.searchParams.append('filters[]', checkbox.value)
      })
    }

    const frame = link.dataset.turboFrame
    if (frame) {
      const frameElement = document.getElementById(frame)
      if (frameElement) {
        frameElement.src = url.toString()
        return
      }
    }

    Turbo.visit(url.toString())
  }
}
