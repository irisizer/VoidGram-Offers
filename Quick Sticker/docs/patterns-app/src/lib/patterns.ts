export type PatternMeta = {
  /** путь к .tgv относительно базы приложения */
  file: string
  /** слаг для вшитых, fileId для кэшевых */
  id: string
  title: string
  origin: string
  width: string
  height: string
  elements: number
  svgBytes: number
  builtin: boolean
}

/** manifest.json генерирует scripts/sync-patterns.py из docs/patterns/*.tgv */
export async function loadManifest(): Promise<PatternMeta[]> {
  const response = await fetch("patterns/manifest.json")
  if (!response.ok) throw new Error(`manifest.json: ${response.status}`)
  return response.json()
}
