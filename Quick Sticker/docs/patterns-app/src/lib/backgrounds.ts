/**
 * Фоновые градиенты — точные наборы из исходников Telegram-iOS.
 * Тап по кадру листает их по кругу.
 */
export type Background = {
  name: string
  colors: number[]
  source: string
}

export const BACKGROUNDS: Background[] = [
  {
    name: "Мятный луг",
    colors: [0xdbddbb, 0x6ba587, 0xd5d88d, 0x88b884],
    source: "обои по умолчанию, Day Classic",
  },
  {
    name: "Неоновая ночь",
    colors: [0x598bf6, 0x7a5eef, 0xd67cff, 0xf38b58],
    source: "обои по умолчанию, тема Night",
  },
  {
    name: "Тёмная сталь",
    colors: [0x1b2836, 0x121a22, 0x1b2836, 0x121a22],
    source: "обои по умолчанию, Night Tinted",
  },
  {
    name: "Сирень",
    colors: [0x8dc0eb, 0xb9d1ea, 0xc6b1ef, 0xebd7ef],
    source: "светлый набор из сетки «Цвета»",
  },
  {
    name: "Ультрамарин",
    colors: [0x8adbf2, 0x888dec, 0xe39fea, 0x679ced],
    source: "светлый набор из сетки «Цвета»",
  },
  {
    name: "Закат",
    colors: [0xeaa36e, 0xf0e486, 0xf29ebf, 0xe8c06e],
    source: "светлый набор из сетки «Цвета»",
  },
  {
    name: "Полночь",
    colors: [0x1e3557, 0x151a36, 0x1c4352, 0x2a4541],
    source: "тёмный набор из сетки «Цвета»",
  },
  {
    name: "Хвойный",
    colors: [0x2d4836, 0x172b19, 0x364331, 0x103231],
    source: "тёмный набор из сетки «Цвета»",
  },
]
