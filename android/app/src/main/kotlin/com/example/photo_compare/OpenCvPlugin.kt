package com.example.photo_compare

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.opencv.android.Utils
import org.opencv.calib3d.Calib3d
import org.opencv.core.*
import org.opencv.features2d.AKAZE
import org.opencv.features2d.BFMatcher
import org.opencv.features2d.ORB
import org.opencv.imgcodecs.Imgcodecs
import org.opencv.imgproc.Imgproc
import org.opencv.video.Video
import java.io.ByteArrayOutputStream
import kotlin.math.*

class OpenCvPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {

    private lateinit var channel: MethodChannel

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, "com.example.photo_compare/opencv")
        channel.setMethodCallHandler(this)
        org.opencv.android.OpenCVLoader.initLocal()
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "perspectiveCorrect" -> {
                    val bytes = call.argument<ByteArray>("bytes")!!
                    result.success(perspectiveCorrect(bytes))
                }
                "alignImages" -> {
                    val ref = call.argument<ByteArray>("reference")!!
                    val src = call.argument<ByteArray>("source")!!
                    result.success(alignImages(ref, src))
                }
                "ssim" -> {
                    val ref = call.argument<ByteArray>("reference")!!
                    val cmp = call.argument<ByteArray>("compare")!!
                    result.success(computeSSIM(ref, cmp))
                }
                "detectCorners" -> {
                    val bytes = call.argument<ByteArray>("bytes")!!
                    result.success(detectCorners(bytes))
                }
                "fuseImages" -> {
                    val ref = call.argument<ByteArray>("reference")!!
                    val src = call.argument<ByteArray>("source")!!
                    result.success(fuseImages(ref, src))
                }
                "compareImages" -> {
                    val ref      = call.argument<ByteArray>("reference")!!
                    val cmp      = call.argument<ByteArray>("compare")!!
                    val wL       = call.argument<Double>("wL")       ?: 0.5
                    val wLayer0  = call.argument<Double>("wLayer0")  ?: 0.5
                    val wLayer1  = call.argument<Double>("wLayer1")  ?: 1.5
                    val wLayer2  = call.argument<Double>("wLayer2")  ?: 2.0
                    val wLayer3  = call.argument<Double>("wLayer3")  ?: 1.0
                    val deScale  = call.argument<Double>("deScale")  ?: 2.0
                    result.success(compareImages(ref, cmp, wL, wLayer0, wLayer1, wLayer2, wLayer3, deScale))
                }
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            result.error("OPENCV_ERROR", e.message, null)
        }
    }

    private fun perspectiveCorrect(bytes: ByteArray): ByteArray {
        val mat = bytesToMat(bytes)
        val gray = Mat()
        Imgproc.cvtColor(mat, gray, Imgproc.COLOR_BGR2GRAY)

        // Более мягкие параметры для реальных фотографий
        Imgproc.GaussianBlur(gray, gray, Size(9.0, 9.0), 0.0)
        Imgproc.Canny(gray, gray, 30.0, 100.0)

        // Закрываем разрывы контуров
        val kernel = Imgproc.getStructuringElement(Imgproc.MORPH_RECT, Size(5.0, 5.0))
        Imgproc.dilate(gray, gray, kernel, Point(-1.0, -1.0), 2)
        Imgproc.erode(gray, gray, kernel, Point(-1.0, -1.0), 1)

        val contours = ArrayList<MatOfPoint>()
        Imgproc.findContours(
            gray, contours, Mat(),
            Imgproc.RETR_EXTERNAL, Imgproc.CHAIN_APPROX_SIMPLE
        )

        val imgArea = mat.width().toDouble() * mat.height()

        // Пробуем разные epsilon пока не найдём четырёхугольник
        var quad: MatOfPoint2f? = null
        for (eps in listOf(0.02, 0.03, 0.04, 0.05, 0.06)) {
            quad = contours
                .map { c ->
                    val c2f = MatOfPoint2f(*c.toArray())
                    val approx = MatOfPoint2f()
                    Imgproc.approxPolyDP(c2f, approx, eps * Imgproc.arcLength(c2f, true), true)
                    approx
                }
                .filter { it.rows() == 4 && Imgproc.contourArea(it) > imgArea * 0.15 }
                .maxByOrNull { Imgproc.contourArea(it) }
            if (quad != null) break
        }

        if (quad == null) return matToBytes(mat)

        val pts = orderPoints(quad.toArray())
        val (tl, tr, br, bl) = pts

        val ww = max(
            sqrt((br.x - bl.x).pow(2) + (br.y - bl.y).pow(2)),
            sqrt((tr.x - tl.x).pow(2) + (tr.y - tl.y).pow(2))
        )
        val hh = max(
            sqrt((tr.x - br.x).pow(2) + (tr.y - br.y).pow(2)),
            sqrt((tl.x - bl.x).pow(2) + (tl.y - bl.y).pow(2))
        )

        // Отбрасываем явно некорректные результаты
        if (ww < 50 || hh < 50 || ww > mat.width() * 2 || hh > mat.height() * 2) {
            return matToBytes(mat)
        }

        val dst = MatOfPoint2f(
            Point(0.0, 0.0), Point(ww - 1, 0.0),
            Point(ww - 1, hh - 1), Point(0.0, hh - 1)
        )
        val src2f = MatOfPoint2f(*pts.toTypedArray())
        val M = Imgproc.getPerspectiveTransform(src2f, dst)
        val warped = Mat()
        Imgproc.warpPerspective(mat, warped, M, Size(ww, hh))
        return matToBytes(warped)
    }

    private fun orderPoints(pts: Array<Point>): List<Point> {
        // TL = наименьшая сумма x+y, BR = наибольшая
        val sumSorted = pts.sortedBy { it.x + it.y }
        val tl = sumSorted[0]
        val br = sumSorted[3]
        // TR = наибольшая разница x-y, BL = наименьшая
        // (TR: x велик, y мал → x-y велико; BL: x мал, y велик → x-y мало)
        val diffSorted = pts.sortedBy { it.x - it.y }
        val bl = diffSorted[0]
        val tr = diffSorted[3]
        return listOf(tl, tr, br, bl)
    }

    private fun alignImages(refBytes: ByteArray, srcBytes: ByteArray): ByteArray {
        val ref = bytesToMat(refBytes)
        val src = bytesToMat(srcBytes)

        val maxSide = 512.0
        val scale = minOf(maxSide / ref.width(), maxSide / ref.height(), 1.0)
        val smallW = (ref.width() * scale).toInt()
        val smallH = (ref.height() * scale).toInt()

        val refSmall = Mat(); val srcSmall = Mat()
        Imgproc.resize(ref, refSmall, Size(smallW.toDouble(), smallH.toDouble()))
        Imgproc.resize(src, srcSmall, Size(smallW.toDouble(), smallH.toDouble()))

        val refGray = Mat(); val srcGray = Mat()
        Imgproc.cvtColor(refSmall, refGray, Imgproc.COLOR_BGR2GRAY)
        Imgproc.cvtColor(srcSmall, srcGray, Imgproc.COLOR_BGR2GRAY)

        refGray.convertTo(refGray, CvType.CV_32F)
        srcGray.convertTo(srcGray, CvType.CV_32F)

        // EUCLIDEAN: только сдвиг + поворот — стабильнее AFFINE для съёмки с руки
        val warpMatrix = Mat.eye(2, 3, CvType.CV_32F)
        val criteria = TermCriteria(TermCriteria.COUNT + TermCriteria.EPS, 100, 1e-4)

        return try {
            Video.findTransformECC(refGray, srcGray, warpMatrix,
                Video.MOTION_EUCLIDEAN, criteria, Mat(), 5)

            // Проверяем угол поворота: если > 15° — трансформ неверный, отдаём оригинал
            val angleDeg = Math.toDegrees(Math.atan2(
                warpMatrix.get(1, 0)[0], warpMatrix.get(0, 0)[0]))
            if (Math.abs(angleDeg) > 15.0) return matToBytes(src)

            // Масштабируем сдвиг под полный размер
            warpMatrix.put(0, 2, warpMatrix.get(0, 2)[0] / scale)
            warpMatrix.put(1, 2, warpMatrix.get(1, 2)[0] / scale)

            val aligned = Mat()
            // Без WARP_INVERSE_MAP — ECC уже даёт прямое преобразование src→ref
            Imgproc.warpAffine(src, aligned, warpMatrix, ref.size(), Imgproc.INTER_LINEAR)
            matToBytes(aligned)
        } catch (e: Exception) {
            matToBytes(src)
        }
    }

    private fun computeSSIM(refBytes: ByteArray, cmpBytes: ByteArray): Double {
        val ref = bytesToMat(refBytes)
        val cmp = bytesToMat(cmpBytes)

        val size = Size(256.0, 256.0)
        val r = Mat(); val c = Mat()
        Imgproc.resize(ref, r, size)
        Imgproc.resize(cmp, c, size)

        val rF = Mat(); val cF = Mat()
        r.convertTo(rF, CvType.CV_64F)
        c.convertTo(cF, CvType.CV_64F)

        val C1 = 6.5025; val C2 = 58.5225

        val mu1 = Mat(); val mu2 = Mat()
        val ksize = Size(11.0, 11.0)
        Imgproc.GaussianBlur(rF, mu1, ksize, 1.5)
        Imgproc.GaussianBlur(cF, mu2, ksize, 1.5)

        val mu1Sq = Mat(); Core.multiply(mu1, mu1, mu1Sq)
        val mu2Sq = Mat(); Core.multiply(mu2, mu2, mu2Sq)
        val mu1mu2 = Mat(); Core.multiply(mu1, mu2, mu1mu2)

        val sigma1Sq = Mat(); val sigma2Sq = Mat(); val sigma12 = Mat()
        val tmp = Mat()

        Core.multiply(rF, rF, tmp)
        Imgproc.GaussianBlur(tmp, sigma1Sq, ksize, 1.5)
        Core.subtract(sigma1Sq, mu1Sq, sigma1Sq)

        Core.multiply(cF, cF, tmp)
        Imgproc.GaussianBlur(tmp, sigma2Sq, ksize, 1.5)
        Core.subtract(sigma2Sq, mu2Sq, sigma2Sq)

        Core.multiply(rF, cF, tmp)
        Imgproc.GaussianBlur(tmp, sigma12, ksize, 1.5)
        Core.subtract(sigma12, mu1mu2, sigma12)

        val num = Mat(); val den = Mat()
        Core.multiply(mu1mu2, Scalar(2.0), num)
        Core.add(num, Scalar(C1), num)
        val num2 = Mat()
        Core.multiply(sigma12, Scalar(2.0), num2)
        Core.add(num2, Scalar(C2), num2)
        Core.multiply(num, num2, num)

        Core.add(mu1Sq, mu2Sq, den)
        Core.add(den, Scalar(C1), den)
        val den2 = Mat()
        Core.add(sigma1Sq, sigma2Sq, den2)
        Core.add(den2, Scalar(C2), den2)
        Core.multiply(den, den2, den)

        val ssimMap = Mat()
        Core.divide(num, den, ssimMap)

        val channels = ArrayList<Mat>()
        Core.split(ssimMap, channels)
        val mean = channels.map { Core.mean(it).`val`[0] }.average()
        return (mean * 100).coerceIn(0.0, 100.0)
    }

    private fun detectCorners(bytes: ByteArray): List<Map<String, Double>>? {
        val mat = bytesToMat(bytes)
        val gray = Mat()
        Imgproc.cvtColor(mat, gray, Imgproc.COLOR_BGR2GRAY)
        Imgproc.GaussianBlur(gray, gray, Size(5.0, 5.0), 0.0)
        Imgproc.Canny(gray, gray, 75.0, 200.0)

        val contours = ArrayList<MatOfPoint>()
        Imgproc.findContours(gray, contours, Mat(), Imgproc.RETR_EXTERNAL, Imgproc.CHAIN_APPROX_SIMPLE)

        val imgArea = mat.width().toDouble() * mat.height()
        val quad = contours
            .map { c -> MatOfPoint2f(*c.toArray()) }
            .mapNotNull { c2f ->
                val approx = MatOfPoint2f()
                Imgproc.approxPolyDP(c2f, approx, 0.02 * Imgproc.arcLength(c2f, true), true)
                if (approx.rows() == 4) approx else null
            }
            .filter { Imgproc.contourArea(it) > imgArea * 0.1 }
            .maxByOrNull { Imgproc.contourArea(it) } ?: return null

        return quad.toArray().map { mapOf("x" to it.x, "y" to it.y) }
    }

    // ── Слияние двух снимков одного объекта ──────────────────────────────────
    private fun fuseImages(refBytes: ByteArray, srcBytes: ByteArray): ByteArray {
        return try {
            fuseImagesInternal(refBytes, srcBytes)
        } catch (e: Exception) {
            matToBytes(bytesToMat(refBytes)) // fallback — не крашим приложение
        }
    }

    private fun fuseImagesInternal(refBytes: ByteArray, srcBytes: ByteArray): ByteArray {
        val refOrig = bytesToMat(refBytes)
        val srcOrig = bytesToMat(srcBytes)

        // Работаем на 1024px
        val maxSide = 1024.0
        val s = minOf(maxSide / refOrig.width(), maxSide / refOrig.height(), 1.0)
        val ref = Mat(); val src = Mat()
        Imgproc.resize(refOrig, ref, Size(refOrig.width() * s, refOrig.height() * s))
        Imgproc.resize(srcOrig, src, Size(srcOrig.width() * s, srcOrig.height() * s))

        val refG = Mat(); val srcG = Mat()
        Imgproc.cvtColor(ref, refG, Imgproc.COLOR_BGR2GRAY)
        Imgproc.cvtColor(src, srcG, Imgproc.COLOR_BGR2GRAY)

        // ── Шаг 1: ORB — грубое совмещение ──────────────────────────────────
        val orb = ORB.create(3000)
        val kpRef = MatOfKeyPoint(); val kpSrc = MatOfKeyPoint()
        val dRef = Mat(); val dSrc = Mat()
        orb.detectAndCompute(refG, Mat(), kpRef, dRef)
        orb.detectAndCompute(srcG, Mat(), kpSrc, dSrc)

        if (dRef.rows() < 10 || dSrc.rows() < 10) return matToBytes(ref)

        val matcher = BFMatcher.create(Core.NORM_HAMMING)
        val knnMatches = ArrayList<MatOfDMatch>()
        matcher.knnMatch(dRef, dSrc, knnMatches, 2)
        val good = knnMatches
            .filter { it.rows() >= 2 }
            .mapNotNull { m ->
                val a = m.toArray()
                if (a[0].distance < 0.75f * a[1].distance) a[0] else null
            }

        if (good.size < 8) return matToBytes(ref)

        val kpRA = kpRef.toArray(); val kpSA = kpSrc.toArray()
        val ptRef2f = MatOfPoint2f(*good.map { kpRA[it.queryIdx].pt }.toTypedArray())
        val ptSrc2f = MatOfPoint2f(*good.map { kpSA[it.trainIdx].pt }.toTypedArray())

        // ── Шаг 2: Homography + warpPerspective — устраняем перспективу ─────
        val H = Calib3d.findHomography(ptSrc2f, ptRef2f, Calib3d.RANSAC, 3.0)
        if (H.empty()) return matToBytes(ref)

        // Проверка гомографии: детерминант < 0 = отражение/переворот → отклоняем
        val det = H.get(0,0)[0] * H.get(1,1)[0] - H.get(0,1)[0] * H.get(1,0)[0]
        if (det < 0) return matToBytes(ref)

        // Проверка: углы src не должны уходить далеко за пределы ref
        val srcCorners = MatOfPoint2f(
            Point(0.0, 0.0), Point(src.width().toDouble(), 0.0),
            Point(src.width().toDouble(), src.height().toDouble()),
            Point(0.0, src.height().toDouble()))
        val dstCorners = MatOfPoint2f()
        Core.perspectiveTransform(srcCorners, dstCorners, H)
        val maxDim = maxOf(ref.width(), ref.height()).toDouble()
        if (dstCorners.toArray().any {
            it.x < -maxDim || it.x > 2 * maxDim ||
            it.y < -maxDim || it.y > 2 * maxDim }) return matToBytes(ref)

        val coarse = Mat()
        Imgproc.warpPerspective(src, coarse, H, ref.size())

        // Маска валидных пикселей после деформации
        val srcMask = Mat.ones(src.rows(), src.cols(), CvType.CV_8U)
        val warpedMask = Mat()
        Imgproc.warpPerspective(srcMask, warpedMask, H, ref.size(), Imgproc.INTER_NEAREST)

        // ── Шаг 3: ECC refinement — субпиксельное уточнение ─────────────────
        // После Homography остаётся только мелкий остаточный сдвиг — ECC его устраняет
        val refF = Mat(); val coarseF = Mat()
        refG.convertTo(refF, CvType.CV_32F)
        val coarseG = Mat(); Imgproc.cvtColor(coarse, coarseG, Imgproc.COLOR_BGR2GRAY)
        coarseG.convertTo(coarseF, CvType.CV_32F)

        val warpMatrix = Mat.eye(2, 3, CvType.CV_32F)
        val criteria = TermCriteria(TermCriteria.COUNT + TermCriteria.EPS, 50, 1e-4)
        val refined = try {
            Video.findTransformECC(refF, coarseF, warpMatrix,
                Video.MOTION_EUCLIDEAN, criteria, Mat(), 5)
            // Проверка: ECC не должен давать большой поворот на уже выровненных снимках
            val angle = Math.toDegrees(Math.atan2(
                warpMatrix.get(1, 0)[0], warpMatrix.get(0, 0)[0]))
            if (Math.abs(angle) > 5.0) coarse  // ECC ушёл не туда — берём coarse
            else {
                val r = Mat()
                Imgproc.warpAffine(coarse, r, warpMatrix, ref.size(), Imgproc.INTER_LINEAR)
                // Уточняем маску тоже
                Imgproc.warpAffine(warpedMask, warpedMask, warpMatrix, ref.size(),
                    Imgproc.INTER_NEAREST)
                r
            }
        } catch (e: Exception) {
            coarse  // ECC не сошёлся — coarse достаточно
        }

        // ── Шаг 4: Взвешенное слияние по резкости ───────────────────────────
        val warpedMask64 = Mat()
        warpedMask.convertTo(warpedMask64, CvType.CV_64F)

        val sharp1 = sharpnessMap(ref)
        val sharp2raw = sharpnessMap(refined)
        val sharp2 = Mat(); Core.multiply(sharp2raw, warpedMask64, sharp2)

        val ref64 = Mat(); val refined64 = Mat()
        ref.convertTo(ref64, CvType.CV_64F)
        refined.convertTo(refined64, CvType.CV_64F)

        val s1List = ArrayList<Mat>().also { it.add(sharp1); it.add(sharp1); it.add(sharp1) }
        val s2List = ArrayList<Mat>().also { it.add(sharp2); it.add(sharp2); it.add(sharp2) }
        val s1c = Mat(); val s2c = Mat()
        Core.merge(s1List, s1c); Core.merge(s2List, s2c)

        val n1 = Mat(); Core.multiply(ref64, s1c, n1)
        val n2 = Mat(); Core.multiply(refined64, s2c, n2)
        val num = Mat(); Core.add(n1, n2, num)
        val den = Mat(); Core.add(s1c, s2c, den)
        Core.add(den, Scalar(1e-6, 1e-6, 1e-6), den)

        val result64 = Mat(); Core.divide(num, den, result64)
        val result = Mat(); result64.convertTo(result, CvType.CV_8U)

        return matToBytes(result)
    }

    // Карта локальной резкости: дисперсия Лапласиана, нормализована 0..1
    private fun sharpnessMap(mat: Mat): Mat {
        val gray = Mat()
        Imgproc.cvtColor(mat, gray, Imgproc.COLOR_BGR2GRAY)
        gray.convertTo(gray, CvType.CV_64F)
        val lap = Mat()
        Imgproc.Laplacian(gray, lap, CvType.CV_64F, 3)
        val lapSq = Mat(); Core.multiply(lap, lap, lapSq)
        val local = Mat()
        Imgproc.GaussianBlur(lapSq, local, Size(65.0, 65.0), 0.0)
        val norm = Mat()
        Core.normalize(local, norm, 0.0, 1.0, Core.NORM_MINMAX, CvType.CV_64F)
        return norm
    }

    // ── Lab-пирамида: иерархическое сравнение в CIELab ──────────────────────
    // Level 3 вычисляется из пикселей; Level 2/1/0 — снизу вверх через RMS.
    // Формула ΔE на зону: √(wL·ΔL² + Δa² + Δb²)  (реальные единицы CIELab)
    // Агрегация 9 дочерних → родитель: RMS = √(Σ ΔEᵢ² / 9)
    private fun compareImages(
        refBytes: ByteArray, cmpBytes: ByteArray,
        wL: Double,
        wLayer0: Double, wLayer1: Double, wLayer2: Double, wLayer3: Double,
        deScale: Double
    ): Map<String, Any> {
        val SIZE = 810  // 27×30 — делится на 1, 3, 9, 27

        val refMat = bytesToMat(refBytes)
        val cmpMat = bytesToMat(cmpBytes)

        val refCrp = labFitCrop(refMat, SIZE)
        val cmpCrp = labFitCrop(cmpMat, SIZE)

        val refLab = Mat(); val cmpLab = Mat()
        Imgproc.cvtColor(refCrp, refLab, Imgproc.COLOR_BGR2Lab)
        Imgproc.cvtColor(cmpCrp, cmpLab, Imgproc.COLOR_BGR2Lab)

        val refF = Mat(); val cmpF = Mat()
        refLab.convertTo(refF, CvType.CV_32F)
        cmpLab.convertTo(cmpF, CvType.CV_32F)

        val refCh = ArrayList<Mat>(); Core.split(refF, refCh)
        val cmpCh = ArrayList<Mat>(); Core.split(cmpF, cmpCh)

        // Снизу вверх: Level 3 из пикселей, выше — RMS агрегация
        val de3 = zoneDE(refCh, cmpCh, SIZE, 27, wL)  // 729 зон (27×27)
        val de2 = aggregateRMS(de3, 27, 3)             //  81 зона ( 9×9 )
        val de1 = aggregateRMS(de2,  9, 3)             //   9 зон  ( 3×3 )
        val de0 = aggregateRMS(de1,  3, 3)             //   1 зона ( 1×1 )

        fun score(de: DoubleArray) = de.map { (100.0 - it * deScale).coerceIn(0.0, 100.0) }.average()
        val wSum = wLayer0 + wLayer1 + wLayer2 + wLayer3
        val overall = if (wSum > 0)
            (score(de0)*wLayer0 + score(de1)*wLayer1 + score(de2)*wLayer2 + score(de3)*wLayer3) / wSum
        else score(de1)

        return mapOf(
            "score"     to overall.coerceIn(0.0, 100.0),
            "level0"    to de0,
            "level1"    to de1,
            "level2"    to de2,
            "level3"    to de3,
            "diffImage" to buildZoneDiff(de2, 9, 30),   // 270×270 PNG
        )
    }

    // Среднеквадратичная агрегация: factor×factor дочерних → 1 родительская зона
    // sourceGrid — размер входной сетки (например 27 для 27×27)
    private fun aggregateRMS(de: DoubleArray, sourceGrid: Int, factor: Int): DoubleArray {
        val tg = sourceGrid / factor
        val result = DoubleArray(tg * tg)
        for (row in 0 until tg) {
            for (col in 0 until tg) {
                var sumSq = 0.0
                for (dr in 0 until factor) {
                    for (dc in 0 until factor) {
                        val v = de[(row * factor + dr) * sourceGrid + (col * factor + dc)]
                        sumSq += v * v
                    }
                }
                result[row * tg + col] = sqrt(sumSq / (factor * factor))
            }
        }
        return result
    }

    // Масштаб по короткой стороне + центральный кроп до size×size
    private fun labFitCrop(src: Mat, size: Int): Mat {
        val scale = if (src.width() < src.height()) size.toDouble() / src.width()
                    else size.toDouble() / src.height()
        val nw = (src.width()  * scale).toInt()
        val nh = (src.height() * scale).toInt()
        val resized = Mat()
        Imgproc.resize(src, resized, Size(nw.toDouble(), nh.toDouble()))
        val cx = ((resized.width()  - size) / 2).coerceAtLeast(0)
        val cy = ((resized.height() - size) / 2).coerceAtLeast(0)
        return Mat(resized, Rect(cx, cy, size, size))
    }

    // Вычисляет ΔE для каждой из grid×grid зон изображения
    // OpenCV Lab: L∈[0,255] (реальный L*=pixel*100/255), a/b∈[0,255] (offset 128)
    private fun zoneDE(
        refCh: List<Mat>, cmpCh: List<Mat>,
        size: Int, grid: Int, wL: Double
    ): DoubleArray {
        val zs = size / grid
        val result = DoubleArray(grid * grid)
        for (row in 0 until grid) {
            for (col in 0 until grid) {
                val rect = Rect(col * zs, row * zs, zs, zs)
                val rL = Core.mean(Mat(refCh[0], rect)).`val`[0]
                val ra = Core.mean(Mat(refCh[1], rect)).`val`[0]
                val rb = Core.mean(Mat(refCh[2], rect)).`val`[0]
                val cL = Core.mean(Mat(cmpCh[0], rect)).`val`[0]
                val ca = Core.mean(Mat(cmpCh[1], rect)).`val`[0]
                val cb = Core.mean(Mat(cmpCh[2], rect)).`val`[0]
                // Перевод в реальные единицы CIELab
                val dL = (rL - cL) * 100.0 / 255.0
                val da = ra - ca   // смещение 128 взаимно сокращается
                val db = rb - cb
                result[row * grid + col] = sqrt(wL * dL * dL + da * da + db * db)
            }
        }
        return result
    }

    // Визуализация diff: cellPx×cellPx пикселей на зону, PNG с прозрачностью
    // Каналы Mat: (R, G, B, A) — PNG-декодер Flutter читает в этом порядке как RGBA
    private fun buildZoneDiff(de: DoubleArray, grid: Int, cellPx: Int): ByteArray {
        val sz = grid * cellPx
        val out = Mat(sz, sz, CvType.CV_8UC4, Scalar(0.0, 0.0, 0.0, 0.0))
        for (i in de.indices) {
            val row = i / grid; val col = i % grid
            val d = de[i]
            val r: Int; val g: Int; val b: Int; val a: Int
            when {
                d < 2.0  -> { r=30;  g=200; b=30;  a=(d/2.0*90).toInt() }
                d < 10.0 -> {
                    val t = (d - 2.0) / 8.0
                    r=(30  + (225*t)).toInt()
                    g=(200 - (30 *t)).toInt()
                    b=30
                    a=(90  + (120*t)).toInt()
                }
                else     -> { r=220; g=20;  b=20;  a=210 }
            }
            out.submat(Rect(col*cellPx, row*cellPx, cellPx, cellPx))
               .setTo(Scalar(r.toDouble(), g.toDouble(), b.toDouble(), a.toDouble()))
        }
        val buf = MatOfByte()
        Imgcodecs.imencode(".png", out, buf)
        return buf.toArray()
    }

    private fun bytesToMat(bytes: ByteArray): Mat {
        val bmp = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
        val mat = Mat()
        Utils.bitmapToMat(bmp, mat)
        Imgproc.cvtColor(mat, mat, Imgproc.COLOR_RGBA2BGR)
        return mat
    }

    private fun matToBytes(mat: Mat): ByteArray {
        val rgb = Mat()
        Imgproc.cvtColor(mat, rgb, Imgproc.COLOR_BGR2RGB)
        val bmp = Bitmap.createBitmap(mat.cols(), mat.rows(), Bitmap.Config.ARGB_8888)
        Utils.matToBitmap(rgb, bmp)
        val out = ByteArrayOutputStream()
        bmp.compress(Bitmap.CompressFormat.JPEG, 95, out)
        return out.toByteArray()
    }
}
