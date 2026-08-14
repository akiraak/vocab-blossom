import { render, screen } from '@testing-library/react'
import App from './App.tsx'

describe('App', () => {
  it('アプリ名が表示される', () => {
    render(<App />)
    expect(screen.getByRole('heading', { name: 'vocab-blossom' })).toBeInTheDocument()
  })
})
