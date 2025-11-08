/** @type {import('tailwindcss').Config} */
module.exports = {
  darkMode: 'class',
  content: [
    './index.html',
    './src/**/*.{js,jsx,ts,tsx}',
  ],
  theme: {
    extend: {
      fontFamily: {
        sans: ['Inter', 'sans-serif'],
        heading: ['Poppins', 'sans-serif'],
      },
      colors: {
        // Light Mode
        'primary': '#4f46e5',
        'primary-focus': '#4338ca',
        'primary-content': '#ffffff',
        
        'accent': '#10b981',
        'accent-focus': '#059669',
        'accent-content': '#ffffff',

        'base-100': '#f8fafc', // slate-50
        'base-200': '#f1f5f9', // slate-100
        'base-300': '#e2e8f0', // slate-200
        'base-content': '#0f172a', // slate-900
        'base-content-secondary': '#64748b', // slate-500

        // Dark Mode
        'dark-primary': '#6366f1',
        'dark-primary-focus': '#4f46e5',
        'dark-primary-content': '#ffffff',

        'dark-accent': '#34d399',
        'dark-accent-focus': '#10b981',
        'dark-accent-content': '#0f172a',

        'dark-base-100': '#020617', // slate-950
        'dark-base-200': '#1e293b', // slate-800 (Changed from slate-900 to fix color collision)
        'dark-base-300': '#334155', // slate-700 (Adjusted for consistency)
        'dark-base-content': '#f8fafc', // slate-50
        'dark-base-content-secondary': '#94a3b8', // slate-400
      },
      keyframes: {
        gradient: {
          '0%, 100%': { 'background-position': '0% 50%' },
          '50%': { 'background-position': '100% 50%' },
        },
      },
      animation: {
        gradient: 'gradient 15s ease infinite',
      },
    },
  },
  plugins: [
    require('@tailwindcss/forms'),
  ],
};
