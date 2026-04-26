module.exports = {
  plugins: [
    require('daisyui')
  ],
  daisyui: {
    themes: [
      {
        docuseal: {
          'color-scheme': 'light',
          primary: '#FF6A3D',
          secondary: '#6b7280',
          accent: '#FF6A3D',
          neutral: '#E0D7C7',
          'base-100': '#F4EFE6',
          'base-200': '#FFFFFF',
          'base-300': '#E0D7C7',
          'base-content': '#1F1B14',
          '--rounded-btn': '0.25rem',
          '--tab-border': '2px',
          '--tab-radius': '.5rem'
        }
      }
    ]
  }
}
