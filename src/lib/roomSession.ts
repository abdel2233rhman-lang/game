const STORAGE_KEY = 'risk-it:session-token';

export function getStoredToken(): string | null {
  return localStorage.getItem(STORAGE_KEY);
}

export function storeToken(token: string): void {
  localStorage.setItem(STORAGE_KEY, token);
}

export function clearStoredToken(): void {
  localStorage.removeItem(STORAGE_KEY);
}
