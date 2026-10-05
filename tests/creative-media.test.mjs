import assert from 'node:assert/strict'
import { createHash } from 'node:crypto'
import { readFileSync, readdirSync, statSync } from 'node:fs'
import { test } from 'node:test'

const media = new URL('../public/media/creative/', import.meta.url)
const manifest = JSON.parse(readFileSync(new URL('gallery.json', media), 'utf8'))

test('showcase has a varied, reusable image/video manifest', () => {
  assert.equal(manifest.items.length, 9)
  assert.equal(manifest.items.filter((item) => item.type === 'image').length, 8)
  assert.equal(manifest.items.filter((item) => item.type === 'video').length, 1)
  assert.equal(new Set(manifest.items.map((item) => item.id)).size, manifest.items.length)
  assert.ok(manifest.cycleDuration >= 12 && manifest.cycleDuration <= 20)
  assert.ok(manifest.items.some((item) => item.columnSpan === 2))
  assert.ok(manifest.items.some((item) => item.aspectRatio < 1))
  assert.ok(manifest.items.some((item) => item.aspectRatio > 2))
  for (const item of manifest.items) {
    assert.match(item.source, /^[a-zA-Z0-9_-]+\.(jpg|mp4)$/)
    assert.ok(item.aspectRatio >= 0.5 && item.aspectRatio <= 3)
    assert.ok([1, 2].includes(item.columnSpan))
    assert.ok(item.altText.length > 10)
  }
})

test('every preview is local, nonempty, correctly encoded, and within the bundle budget', () => {
  let totalBytes = 0
  for (const item of manifest.items) {
    for (const name of [item.source, item.poster].filter(Boolean)) {
      const data = readFileSync(new URL(name, media))
      totalBytes += data.length
      assert.ok(data.length > 1000)
      if (name.endsWith('.mp4')) {
        assert.equal(data.toString('ascii', 4, 8), 'ftyp')
        assert.ok(data.length < 1024 * 1024, 'preview must remain below 1 MiB')
      } else {
        assert.equal(data.readUInt16BE(0), 0xffd8)
        assert.equal(data.readUInt16BE(data.length - 2), 0xffd9)
        assert.ok(data.length < 400 * 1024)
      }
    }
  }
  assert.ok(totalBytes < 3 * 1024 * 1024, 'showcase media must remain below 3 MiB')
  assert.ok(!readdirSync(media).some((name) => name.includes('.sb-') || name.startsWith('.preview-')),
    'AVFoundation scratch output must not be shipped')
})

test('supplied video is preserved, while the gallery uses a portrait derivative with a poster', () => {
  const source = new URL('../assets/creative/quwati-original.mp4', import.meta.url)
  assert.equal(createHash('sha256').update(readFileSync(source)).digest('hex'),
    '9f392ad8945073966cad747e6d8aab93f49faf04ed3974470eb14620988c8be6')
  const video = manifest.items.find((item) => item.type === 'video')
  assert.equal(video.source, 'quwati-preview.mp4')
  assert.equal(video.poster, 'quwati-poster.jpg')
  assert.equal(video.columnSpan, 1)
  assert.ok(Math.abs(video.aspectRatio - 280 / 512) < 0.01)
  assert.ok(statSync(new URL(video.source, media)).size < statSync(source).size)
})
