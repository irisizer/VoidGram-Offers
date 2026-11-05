/**
 * Меш-градиент Telegram — порт submodules/GradientBackground/Sources/SoftwareGradientBackground.swift
 *
 * Восемь базовых точек по кругу; для кадра массив сдвигается на фазу и берётся каждая вторая —
 * остаются четыре точки под четыре цвета. Цвет пикселя — среднее по точкам с весом
 * max(0, 0.92 - dist)^3, посчитанное после поворота координат вокруг центра.
 */

const BASE_POSITIONS: Array<[number, number]> = [
  [0.8, 0.1],
  [0.6, 0.2],
  [0.35, 0.25],
  [0.25, 0.6],
  [0.2, 0.9],
  [0.4, 0.8],
  [0.65, 0.75],
  [0.75, 0.4],
]

export function positionsForPhase(phase: number): Array<[number, number]> {
  const k = ((phase % 8) + 8) % 8
  const shifted = [...BASE_POSITIONS.slice(k), ...BASE_POSITIONS.slice(0, k)]
  const out: Array<[number, number]> = []
  for (let i = 0; i < shifted.length / 2; i++) out.push(shifted[i * 2])
  return out
}

export function hexToRgb(v: number): [number, number, number] {
  return [(v >> 16) & 255, (v >> 8) & 255, v & 255]
}

export function hexStr(v: number): string {
  return "#" + v.toString(16).padStart(6, "0")
}

/** Средняя яркость набора цветов — так же, как UIColor.average(...).hsb.b в клиенте. */
export function averageBrightness(colors: number[]): number {
  let r = 0
  let g = 0
  let b = 0
  for (const v of colors) {
    const c = hexToRgb(v)
    r += c[0]
    g += c[1]
    b += c[2]
  }
  const n = colors.length
  return Math.max(r / n, g / n, b / n) / 255
}

export function drawMesh(
  ctx: CanvasRenderingContext2D,
  width: number,
  height: number,
  colors: number[],
  phase: number,
) {
  if (colors.length === 1) {
    ctx.fillStyle = hexStr(colors[0])
    ctx.fillRect(0, 0, width, height)
    return
  }

  const points = positionsForPhase(phase).map(([x, y]) => [x, 1 - y] as const)
  const rgb = colors.map(hexToRgb)
  const n = Math.min(rgb.length, points.length)
  const img = ctx.createImageData(width, height)
  const d = img.data

  for (let y = 0; y < height; y++) {
    const dy = y / height - 0.5
    for (let x = 0; x < width; x++) {
      const dx = x / width - 0.5
      const centerDistance = Math.sqrt(dx * dx + dy * dy)
      const swirl = 0.35 * centerDistance
      const theta = swirl * swirl * 0.8 * 8.0
      const sin = Math.sin(theta)
      const cos = Math.cos(theta)
      const px = Math.min(1, Math.max(0, 0.5 + dx * cos - dy * sin))
      const py = Math.min(1, Math.max(0, 0.5 + dx * sin + dy * cos))

      let sum = 0
      let r = 0
      let g = 0
      let b = 0
      for (let i = 0; i < n; i++) {
        const ddx = px - points[i][0]
        const ddy = py - points[i][1]
        let w = Math.max(0, 0.92 - Math.sqrt(ddx * ddx + ddy * ddy))
        w = w * w * w
        sum += w
        r += w * rgb[i][0]
        g += w * rgb[i][1]
        b += w * rgb[i][2]
      }
      if (sum < 1e-5) sum = 1e-5

      const o = (y * width + x) * 4
      d[o] = Math.min(255, r / sum)
      d[o + 1] = Math.min(255, g / sum)
      d[o + 2] = Math.min(255, b / sum)
      d[o + 3] = 255
    }
  }
  ctx.putImageData(img, 0, 0)
}

/** Распаковка .tgv (gzip-SVG) в blob-URL, годный для CSS-маски. */
export async function loadTgv(url: string): Promise<string> {
  const response = await fetch(url)
  if (!response.body) throw new Error("пустой ответ")
  const svg = await new Response(
    response.body.pipeThrough(new DecompressionStream("gzip")),
  ).text()
  return URL.createObjectURL(new Blob([svg], { type: "image/svg+xml" }))
}
