/** @type {import('tailwindcss').Config} */
export default {
  content: ['./index.html', './src/**/*.{js,ts,jsx,tsx}'],
  theme: {
    extend: {
      colors: {
        ink: {
          950: '#050507',
          900: '#0a0a0f',
          800: '#11111a',
          700: '#1a1a26',
          600: '#262636',
          500: '#3a3a4f',
          400: '#7a7a92',
          300: '#a3a3b8',
          200: '#c9c9d8',
          100: '#f0f0f7',
        },
        neon: {
          300: '#d8b4fe',
          400: '#c084fc',
          500: '#a855f7',
          600: '#9333ea',
          700: '#7e22ce',
        },
        electric: {
          400: '#a78bfa',
          500: '#8b5cf6',
        },
        gold: {
          200: '#fde68a',
          300: '#fcd34d',
          400: '#f5c542',
          500: '#d4a017',
        },
      },
      fontFamily: {
        sans: ['Cairo', 'system-ui', 'sans-serif'],
        display: ['Orbitron', 'Cairo', 'sans-serif'],
      },
      keyframes: {
        float: {
          '0%, 100%': { transform: 'translate3d(0, 0, 0) scale(1)' },
          '50%': { transform: 'translate3d(24px, -32px, 0) scale(1.08)' },
        },
        'glow-pulse': {
          '0%, 100%': { opacity: '0.55' },
          '50%': { opacity: '1' },
        },
        'shine-sweep': {
          '0%': { transform: 'translateX(-120%) skewX(-20deg)' },
          '100%': { transform: 'translateX(220%) skewX(-20deg)' },
        },
      },
      animation: {
        float: 'float 14s ease-in-out infinite',
        'float-slow': 'float 22s ease-in-out infinite reverse',
        'glow-pulse': 'glow-pulse 3s ease-in-out infinite',
        'shine-sweep': 'shine-sweep 3.2s ease-in-out infinite',
      },
      boxShadow: {
        neon: '0 0 24px rgba(168, 85, 247, 0.45), 0 0 60px rgba(139, 92, 246, 0.2)',
        gold: '0 0 24px rgba(245, 197, 66, 0.35)',
      },
    },
  },
  plugins: [],
};
