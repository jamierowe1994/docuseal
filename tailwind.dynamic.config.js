const path = require('path')

module.exports = {
  content: [
    path.resolve(__dirname, 'app/javascript/template_builder/dynamic_area.vue'),
    path.resolve(__dirname, 'app/javascript/template_builder/dynamic_section.vue')
  ],
  theme: {
    extend: {
      colors: {
        'base-100': '#F4EFE6',
        'base-200': '#FFFFFF',
        'base-300': '#E0D7C7',
        'base-content': '#1F1B14'
      }
    }
  }
}
