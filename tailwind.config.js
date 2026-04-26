module.exports = {
  plugins: [
    require('daisyui')
  ],
  daisyui: {
    themes: [
      {
        docuseal: {
          'color-scheme': 'dark',
          primary: '#8bc34a',
          secondary: '#6b7280',
          accent: '#8bc34a',
          neutral: '#1f2937',
          'base-100': '#111111',
          'base-200': '#1a1a1a',
          'base-300': '#2a2a2a',
          'base-content': '#e5e7eb',
          '--rounded-btn': '0.25rem',
          '--tab-border': '2px',
          '--tab-radius': '.5rem'
        }
      }
    ]
  }
}
