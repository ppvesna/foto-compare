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
                "alignPyramid" -> {
                    val ref = call.argument<ByteArray>("reference")!!
                    val src = call.argument<ByteArray>("source")!!
                    result.success(alignPyramid(ref, src))
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
                "stitchImages" -> {
                    val imgA = call.argument<ByteArray>("imageA")!!
                    val imgB = call.argument<ByteArray>("imageB")!!
                    val wL   = call.argument<Double>("wL") ?: 0.5
                    result.success(stitchImages(imgA, imgB, wL))
                }
                "compareImages" -> {                    val ref      = call.argument<ByteArray>("reference")!!
                    val cmp      = call.argument<ByteArray>("compare")!!
                    val wL       = call.argument<Double>("wL")       ?: 0.5
                    val wLayer0  = call.argument<Double>("wLayer0")  ?: 0.5
                    val wLayer1  = call.argument<Double>("wLayer1")  ?: 1.5
                    val wLayer2  = call.argument<Double>("wLayer2")  ?: 2.0
                    val wLayer3  = call.argument<Double>("wLayer3")  ?: 1.0
                    val deScale  = call.argument<Double>("deScale")  ?: 2.0
                    val widthMm  = call.argument<Double>("widthMm")  ?: 100.0
                    val heightMm = call.argument<Double>("heightMm") ?: 100.0
                    result.success(compareImages(ref, cmp, wL, wLayer0, wLayer1, wLayer2, wLayer3, deScale, widthMm, heightMm))
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

    // Пирамидное выравнивание для съёмки с руки.
    // Шаг 1: AKAZE + Lowe ratio test → полная гомография → warpPerspective.
    //   Обрабатывает сдвиг, поворот и перспективную деформацию.
    // Шаг 2: ECC-пирамида L3→L0 — субпиксельное уточнение остатка.
    private fun alignPyramid(refBytes: ByteArray, srcBytes: ByteArray): ByteArray {
        val ref = bytesToMat(refBytes)
        val src = bytesToMat(srcBytes)

        val refGray = Mat(); Imgproc.cvtColor(ref, refGray, Imgproc.COLOR_BGR2GRAY)
        val srcGray = Mat(); Imgproc.cvtColor(src, srcGray, Imgproc.COLOR_BGR2GRAY)

        // ── Шаг 1: AKAZE + полная гомография ────────────────────────────────
        val maxSide = 1000.0
        val sc = minOf(maxSide / ref.width(), maxSide / ref.height(), 1.0)
        val rS = Mat(); Imgproc.resize(refGray, rS, Size(ref.width() * sc, ref.height() * sc))
        val sS = Mat(); Imgproc.resize(srcGray, sS, Size(src.width() * sc, src.height() * sc))

        val akaze = AKAZE.create()
        val kpR = MatOfKeyPoint(); val kpS = MatOfKeyPoint()
        val dR = Mat(); val dS = Mat()
        akaze.detectAndCompute(rS, Mat(), kpR, dR)
        akaze.detectAndCompute(sS, Mat(), kpS, dS)

        var homography: Mat? = null
        if (!dR.empty() && !dS.empty() && dR.rows() >= 8 && dS.rows() >= 8) {
            // Lowe's ratio test: отбраковывает неоднозначные совпадения
            val matcher = BFMatcher.create(BFMatcher.BRUTEFORCE_HAMMING)
            val knn = ArrayList<MatOfDMatch>()
            matcher.knnMatch(dR, dS, knn, 2)
            val good = knn.filter { it.rows() >= 2 }.mapNotNull { m ->
                m.toArray().let { if (it[0].distance < 0.75f * it[1].distance) it[0] else null }
            }
            if (good.size >= 8) {
                val kpRL = kpR.toList(); val kpSL = kpS.toList()
                val ptR = MatOfPoint2f(); ptR.fromList(good.map { kpRL[it.queryIdx].pt })
                val ptS = MatOfPoint2f(); ptS.fromList(good.map { kpSL[it.trainIdx].pt })
                val Hraw = Calib3d.findHomography(ptS, ptR, Calib3d.RANSAC, 3.0)
                if (!Hraw.empty()) {
                    // Масштабируем гомографию к полному разрешению:
                    // H_full = diag(1/sc,1/sc,1) · Hraw · diag(sc,sc,1)
                    // → tx,ty /= sc; h20,h21 *= sc; остальное без изменений
                    val Hd = Mat(); Hraw.convertTo(Hd, CvType.CV_64F)
                    Hd.put(0, 2, Hd.get(0,2)[0] / sc)
                    Hd.put(1, 2, Hd.get(1,2)[0] / sc)
                    Hd.put(2, 0, Hd.get(2,0)[0] * sc)
                    Hd.put(2, 1, Hd.get(2,1)[0] * sc)
                    homography = Hd
                }
            }
        }

        // warpPerspective: обрабатывает и поворот, и перспективу, и сдвиг
        val coarse = Mat()
        if (homography != null) {
            Imgproc.warpPerspective(src, coarse, homography, ref.size(), Imgproc.INTER_LINEAR)
        } else {
            src.copyTo(coarse)
        }
        val coarseGray = Mat(); Imgproc.cvtColor(coarse, coarseGray, Imgproc.COLOR_BGR2GRAY)

        // ── Шаг 2: ECC-пирамида L3→L0 (субпиксельное уточнение) ─────────────
        // AKAZE уже дал грубое совмещение — ECC устраняет только остаток (< 3°)
        val numLevels = 4
        val pyrRef = ArrayList<Mat>(numLevels)
        val pyrSrc = ArrayList<Mat>(numLevels)
        pyrRef.add(refGray); pyrSrc.add(coarseGray)
        repeat(numLevels - 1) {
            val r = Mat(); Imgproc.pyrDown(pyrRef.last(), r); pyrRef.add(r)
            val s = Mat(); Imgproc.pyrDown(pyrSrc.last(), s); pyrSrc.add(s)
        }

        val eccWarp = Mat.eye(2, 3, CvType.CV_32F)
        val criteria = TermCriteria(TermCriteria.COUNT + TermCriteria.EPS, 50, 1e-4)
        for (lvl in numLevels - 1 downTo 0) {
            val rF = Mat(); pyrRef[lvl].convertTo(rF, CvType.CV_32F)
            val sF = Mat(); pyrSrc[lvl].convertTo(sF, CvType.CV_32F)
            try {
                Video.findTransformECC(rF, sF, eccWarp, Video.MOTION_EUCLIDEAN, criteria, Mat(), 5)
                // После AKAZE остаток малый; если ECC уходит далеко — сбрасываем
                val angle = Math.toDegrees(Math.atan2(eccWarp.get(1,0)[0], eccWarp.get(0,0)[0]))
                if (Math.abs(angle) > 3.0) {
                    eccWarp.put(0,0, 1.0); eccWarp.put(0,1, 0.0); eccWarp.put(0,2, 0.0)
                    eccWarp.put(1,0, 0.0); eccWarp.put(1,1, 1.0); eccWarp.put(1,2, 0.0)
                }
            } catch (ignored: Exception) {}
            if (lvl > 0) {
                eccWarp.put(0, 2, eccWarp.get(0,2)[0] * 2.0)
                eccWarp.put(1, 2, eccWarp.get(1,2)[0] * 2.0)
            }
        }

        return try {
            val refined = Mat()
            Imgproc.warpAffine(coarse, refined, eccWarp, ref.size(), Imgproc.INTER_LINEAR)
            matToBytes(refined)
        } catch (ignored: Exception) {
            matToBytes(coarse)
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

    // ── Сшивка двух кадров с перекрытием ────────────────────────────────────
    // Каскадный поиск перекрытия через Lab-пирамиду (L3→L2→L1),
    // затем пиксельная склейка с линейным блендингом.
    private fun stitchImages(aBytes: ByteArray, bBytes: ByteArray, wL: Double): ByteArray {
        val aOrig = bytesToMat(aBytes)
        val bOrig = bytesToMat(bBytes)

        val H    = 810   // рабочая высота (делится на 27)
        val ZONE = 30    // пикселей в одной зоне Level 3

        // Нормализуем высоту, сохраняем ширину пропорционально
        val aW = (aOrig.width().toDouble() * H / aOrig.height()).toInt()
        val bW = (bOrig.width().toDouble() * H / bOrig.height()).toInt()
        val aMat = Mat(); Imgproc.resize(aOrig, aMat, Size(aW.toDouble(), H.toDouble()))
        val bMat = Mat(); Imgproc.resize(bOrig, bMat, Size(bW.toDouble(), H.toDouble()))

        // Lab-каналы в float
        fun toLabCh(mat: Mat): List<Mat> {
            val lab = Mat(); Imgproc.cvtColor(mat, lab, Imgproc.COLOR_BGR2Lab)
            val f = Mat(); lab.convertTo(f, CvType.CV_32F)
            val ch = ArrayList<Mat>(); Core.split(f, ch); return ch
        }
        val aCh = toLabCh(aMat)
        val bCh = toLabCh(bMat)

        val minOvlp = ZONE * 3                    // минимум 90 px
        val maxOvlp = minOf(aW, bW) * 2 / 3      // максимум 2/3 ширины

        // Среднее ΔE между правым краем A и левым краем B при перекрытии ovlp px
        fun overlapDE(ovlp: Int): Double {
            val w  = ovlp.coerceIn(1, minOf(aW, bW))
            val aX = aW - w
            val dL = Mat(); Core.subtract(
                Mat(aCh[0], Rect(aX, 0, w, H)), Mat(bCh[0], Rect(0, 0, w, H)), dL)
            dL.convertTo(dL, CvType.CV_64F, 100.0 / 255.0)
            val da = Mat(); Core.subtract(
                Mat(aCh[1], Rect(aX, 0, w, H)), Mat(bCh[1], Rect(0, 0, w, H)), da)
            da.convertTo(da, CvType.CV_64F)
            val db = Mat(); Core.subtract(
                Mat(aCh[2], Rect(aX, 0, w, H)), Mat(bCh[2], Rect(0, 0, w, H)), db)
            db.convertTo(db, CvType.CV_64F)
            val dL2 = Mat(); Core.multiply(dL, dL, dL2, wL)
            val da2 = Mat(); Core.multiply(da, da, da2)
            val db2 = Mat(); Core.multiply(db, db, db2)
            val de2 = Mat(); Core.add(dL2, da2, de2); Core.add(de2, db2, de2)
            val deMap = Mat(); Core.sqrt(de2, deMap)
            return Core.mean(deMap).`val`[0]
        }

        // Поиск минимума ΔE на диапазоне [from..to] с шагом step
        fun searchBest(from: Int, to: Int, step: Int): Int {
            var best = from; var bestDE = Double.MAX_VALUE
            var x = from.coerceAtLeast(minOvlp)
            while (x <= to.coerceAtMost(maxOvlp)) {
                val de = overlapDE(x)
                if (de < bestDE) { bestDE = de; best = x }
                x += step
            }
            return best
        }

        // Каскад: Level 1 (шаг 270px) → Level 2 (90px) → Level 3 (30px)
        var ovlp = searchBest(minOvlp, maxOvlp, ZONE * 9)
        ovlp = searchBest(ovlp - ZONE * 9, ovlp + ZONE * 9, ZONE * 3)
        ovlp = searchBest(ovlp - ZONE * 3, ovlp + ZONE * 3, ZONE)

        return stitchAtOverlap(aMat, bMat, ovlp)
    }

    // Склеивает A и B с известным перекрытием overlapW пикселей.
    // В зоне перекрытия — линейный градиентный блендинг A→B.
    private fun stitchAtOverlap(aMat: Mat, bMat: Mat, overlapW: Int): ByteArray {
        val H    = aMat.rows()
        val aW   = aMat.cols()
        val bW   = bMat.cols()
        val outW = aW + bW - overlapW

        val out = Mat(H, outW, CvType.CV_8UC3, Scalar.all(0.0))

        // Полностью копируем A
        aMat.copyTo(Mat(out, Rect(0, 0, aW, H)))

        // Уникальная часть B (правее зоны перекрытия)
        val bUniqueW = bW - overlapW
        if (bUniqueW > 0) {
            Mat(bMat, Rect(overlapW, 0, bUniqueW, H))
                .copyTo(Mat(out, Rect(aW, 0, bUniqueW, H)))
        }

        // Блендинг: float-версии полосы перекрытия
        val aOvlp = Mat()
        Mat(aMat, Rect(aW - overlapW, 0, overlapW, H)).convertTo(aOvlp, CvType.CV_32FC3)
        val bOvlp = Mat()
        Mat(bMat, Rect(0, 0, overlapW, H)).convertTo(bOvlp, CvType.CV_32FC3)

        // Градиент alphaB: 0 → 1 слева направо по ширине перекрытия
        val aRow = FloatArray(overlapW) { col -> col.toFloat() / overlapW }
        val alphaB1 = Mat(1, overlapW, CvType.CV_32F); alphaB1.put(0, 0, aRow)
        val alphaB  = Mat(); Core.repeat(alphaB1, H, 1, alphaB)
        val alphaA  = Mat(); Core.subtract(
            Mat(H, overlapW, CvType.CV_32F, Scalar(1.0)), alphaB, alphaA)

        // Расширяем до 3 каналов
        val wA3 = Mat(); Core.merge(arrayListOf(alphaA, alphaA.clone(), alphaA.clone()), wA3)
        val wB3 = Mat(); Core.merge(arrayListOf(alphaB, alphaB.clone(), alphaB.clone()), wB3)

        val blendF = Mat()
        val pa = Mat(); Core.multiply(aOvlp, wA3, pa)
        val pb = Mat(); Core.multiply(bOvlp, wB3, pb)
        Core.add(pa, pb, blendF)

        val blend8 = Mat(); blendF.convertTo(blend8, CvType.CV_8UC3)
        blend8.copyTo(Mat(out, Rect(aW - overlapW, 0, overlapW, H)))

        return matToBytes(out)
    }

    // ── Lab-пирамида: иерархическое сравнение в CIELab ──────────────────────
    // Оба изображения приводятся к каноническому разрешению (70 л/см × Найквист).
    // Level 3 вычисляется из пикселей; Level 2/1/0 — снизу вверх через RMS.
    // Letterbox-зоны (поля после масштабирования) исключаются из счёта.
    private fun compareImages(
        refBytes: ByteArray, cmpBytes: ByteArray,
        wL: Double,
        wLayer0: Double, wLayer1: Double, wLayer2: Double, wLayer3: Double,
        deScale: Double,
        widthMm: Double, heightMm: Double
    ): Map<String, Any> {
        val GRID = 27

        // Каноническое разрешение от физического размера печати и 70 л/см
        val (nw, nh) = canonicalRes(widthMm, heightMm)

        val refMat = bytesToMat(refBytes)
        val cmpMat = bytesToMat(cmpBytes)

        // Нормализация: масштаб до канонического размера + letterbox
        val refCrp = normalizeToCanonical(refMat, nw, nh)
        val cmpCrp = normalizeToCanonical(cmpMat, nw, nh)

        // Маски пустых зон (letterbox + незаснятые края после сшивки).
        // Зона исключается если в ней нет контента (>50% чёрных пикселей) хотя бы в одном из двух.
        val emptyRef = emptyZones(refCrp, GRID)
        val emptyСmp = emptyZones(cmpCrp, GRID)
        val lb3 = BooleanArray(GRID * GRID) { i -> emptyRef[i] || emptyСmp[i] }
        val lb2 = aggregateMask(lb3, GRID, 3)
        val lb1 = aggregateMask(lb2, GRID / 3, 3)
        val lb0 = aggregateMask(lb1, GRID / 9, 3)

        val refLab = Mat(); val cmpLab = Mat()
        Imgproc.cvtColor(refCrp, refLab, Imgproc.COLOR_BGR2Lab)
        Imgproc.cvtColor(cmpCrp, cmpLab, Imgproc.COLOR_BGR2Lab)

        // Снизу вверх: Level 3 из пикселей, выше — RMS агрегация
        val de3 = zoneDE(refLab, cmpLab, nw, nh, GRID, wL)
        val de2 = aggregateRMS(de3, GRID, 3)
        val de1 = aggregateRMS(de2, GRID / 3, 3)
        val de0 = aggregateRMS(de1, GRID / 9, 3)

        // Счёт только по активным (не letterbox) зонам
        fun score(de: DoubleArray, lb: BooleanArray): Double {
            val active = de.filterIndexed { i, _ -> !lb[i] }
            if (active.isEmpty()) return 100.0
            return active.map { (100.0 - it * deScale).coerceIn(0.0, 100.0) }.average()
        }

        val wSum = wLayer0 + wLayer1 + wLayer2 + wLayer3
        val overall = if (wSum > 0)
            (score(de0,lb0)*wLayer0 + score(de1,lb1)*wLayer1 +
             score(de2,lb2)*wLayer2 + score(de3,lb3)*wLayer3) / wSum
        else score(de1, lb1)

        val activeCnt = lb3.count { !it }

        // Глобальный цветовой сдвиг: средние Lab ref − cmp по всему изображению.
        // Разность не зависит от letterbox (одинаковый у обоих).
        val refLabCh = ArrayList<Mat>(); Core.split(refLab, refLabCh)
        val cmpLabCh = ArrayList<Mat>(); Core.split(cmpLab, cmpLabCh)
        val mRL = Core.mean(refLabCh[0]).`val`[0]; val mCL = Core.mean(cmpLabCh[0]).`val`[0]
        val mRA = Core.mean(refLabCh[1]).`val`[0]; val mCA = Core.mean(cmpLabCh[1]).`val`[0]
        val mRB = Core.mean(refLabCh[2]).`val`[0]; val mCB = Core.mean(cmpLabCh[2]).`val`[0]
        val dL = (mRL - mCL) * (100.0 / 255.0)
        val da = (mRA - mCA)          // в единицах OpenCV a* (нейтраль = 128)
        val db = (mRB - mCB)          // b* аналогично

        return mapOf(
            "score"        to overall.coerceIn(0.0, 100.0),
            "activeZones"  to activeCnt,
            "totalZones"   to (GRID * GRID),
            "level0"       to de0,
            "level1"       to de1,
            "level2"       to de2,
            "level3"       to de3,
            // Цветовой сдвиг для текстовых комментариев
            "shiftDL"      to dL,
            "shiftDA"      to da,
            "shiftDB"      to db,
            // Каноническое ref-изображение для корректного наложения diff-карты
            "refCanonical" to matToBytes(refCrp),
            // Diff-карта L3 (27×27 детали). L1 и L2 → только текст.
            "diffL3"       to buildZoneDiff(de3, GRID, nw, nh),
        )
    }

    // Каноническое разрешение: 70 л/см × 2 (Найквист) = 14 пкс/мм,
    // округлённое до кратного 27 (для трёхуровневой пирамиды 3×3×3).
    private fun canonicalRes(widthMm: Double, heightMm: Double): Pair<Int, Int> {
        val pxPerMm = 14.0  // 70 л/см × 2 / 10 мм/см
        val nw = ceil(widthMm  * pxPerMm / 27).toInt() * 27
        val nh = ceil(heightMm * pxPerMm / 27).toInt() * 27
        return nw to nh
    }

    // Масштабирует изображение до канонического разрешения с letterbox-полями.
    // Всё изображение попадает в кадр (без обрезки), поля заполняются чёрным.
    private fun normalizeToCanonical(src: Mat, nw: Int, nh: Int): Mat {
        val scale = minOf(nw.toDouble() / src.width(), nh.toDouble() / src.height())
        val sw = (src.width()  * scale).roundToInt()
        val sh = (src.height() * scale).roundToInt()
        val scaled = Mat()
        Imgproc.resize(src, scaled, Size(sw.toDouble(), sh.toDouble()))
        val canvas = Mat(nh, nw, src.type(), Scalar.all(0.0))
        val x = (nw - sw) / 2; val y = (nh - sh) / 2
        scaled.copyTo(Mat(canvas, Rect(x, y, sw, sh)))
        return canvas
    }

    // Пиксельная маска пустых зон: true = зона пустая (нет контента).
    // Зона считается пустой если >50% пикселей имеют яркость L_ocv < 20 (почти чёрный).
    // Покрывает: letterbox-поля, незаснятые края после сшивки, stitching-gaps.
    private fun emptyZones(mat: Mat, grid: Int): BooleanArray {
        val gray = Mat()
        // Используем только L-канал (после BGR→Lab преобразования) или просто серый
        Imgproc.cvtColor(mat, gray, Imgproc.COLOR_BGR2GRAY)
        val zw = mat.width()  / grid
        val zh = mat.height() / grid
        val threshold = 20.0
        return BooleanArray(grid * grid) { i ->
            val row = i / grid; val col = i % grid
            val roi = Mat(gray, Rect(col * zw, row * zh, zw, zh))
            val black = Mat(); Core.compare(roi, Scalar(threshold), black, Core.CMP_LT)
            val blackCount = Core.countNonZero(black)
            black.release()
            blackCount > (zw * zh) / 2   // true = зона пустая
        }.also { gray.release() }
    }

    // Агрегирует маску снизу вверх: родительская зона = letterbox,
    // только если ВСЕ factor×factor дочерних зон — letterbox.
    private fun aggregateMask(mask: BooleanArray, sourceGrid: Int, factor: Int): BooleanArray {
        val tg = sourceGrid / factor
        return BooleanArray(tg * tg) { i ->
            val row = i / tg; val col = i % tg
            (0 until factor).all { dr ->
                (0 until factor).all { dc ->
                    mask[(row * factor + dr) * sourceGrid + (col * factor + dc)]
                }
            }
        }
    }

    // ── Вспомогательные методы пирамиды ─────────────────────────────────────

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

    // ── 803-сегментное LCH пространство ─────────────────────────────────────
    // L*: 11 классов [0-100]; C: 7 классов; H: 12 секторов по 30°.
    // Ахроматические (C0): 11 сегментов.
    // Хроматические (C1-C6): 11 × 6 × 12 = 792 сегмента. Итого: 803.
    // Каждый сегмент — фиксированная точка в LCH-пространстве.
    // ΔE вычисляется между центрами доминирующих сегментов зоны.

    private val LS_BOUNDS  = doubleArrayOf(0.0,9.0,18.0,27.0,36.0,45.0,54.0,63.0,72.0,81.0,90.0,101.0)
    private val LS_CENTERS = doubleArrayOf(4.0,13.0,22.0,31.0,40.0,49.0,58.0,67.0,76.0,85.0,95.0)
    private val CR_BOUNDS  = doubleArrayOf(0.0,3.0,11.0,21.0,36.0,51.0,71.0,Double.MAX_VALUE)
    private val CR_CENTERS = doubleArrayOf(1.0,6.5,15.5,28.0,43.0,60.5,80.0)
    private val HC_RAD     = DoubleArray(12) { Math.toRadians(15.0 + it * 30.0) }
    private val N_SEG      = 803

    private fun lStarClass(lStar: Double): Int {
        for (i in 1 until LS_BOUNDS.size) if (lStar < LS_BOUNDS[i]) return i - 1; return 10
    }
    private fun chromaClass(c: Double): Int {
        for (i in 1 until CR_BOUNDS.size) if (c < CR_BOUNDS[i]) return i - 1; return 6
    }
    private fun hueClass(hDeg: Double): Int =
        (((hDeg % 360 + 360) % 360) / 30).toInt().coerceIn(0, 11)

    // ID сегмента: ахроматический (cc==0) → 0-10; хроматический → 11-802
    private fun segId(lc: Int, cc: Int, hc: Int): Int =
        if (cc == 0) lc else 11 + lc * 72 + (cc - 1) * 12 + hc

    // Центр сегмента: (L* [0-100], C [CIE], H [радианы])
    private fun segCenter(id: Int): Triple<Double, Double, Double> = if (id < 11)
        Triple(LS_CENTERS[id], CR_CENTERS[0], 0.0)
    else {
        val i = id - 11
        Triple(LS_CENTERS[i / 72], CR_CENTERS[(i % 72) / 12 + 1], HC_RAD[i % 12])
    }

    // ΔE*ab между центрами двух сегментов
    private fun segDE(idR: Int, idC: Int, wL: Double): Double {
        val (lR, cR, hR) = segCenter(idR)
        val (lC, cC, hC) = segCenter(idC)
        val dL = lR - lC
        val da = cR * cos(hR) - cC * cos(hC)
        val db = cR * sin(hR) - cC * sin(hC)
        return sqrt(wL * dL * dL + da * da + db * db)
    }

    // Доминирующий сегмент зоны: гистограмма 803 бинов → максимум.
    // lab — байтовый массив Mat CV_8UC3 (OpenCV Lab: L∈[0,255], a/b∈[0,255] нейтраль=128).
    private fun dominantSeg(lab: ByteArray, imgW: Int, zx: Int, zy: Int, zw: Int, zh: Int): Int {
        val hist = IntArray(N_SEG)
        for (dy in 0 until zh) {
            val rowBase = (zy + dy) * imgW
            for (dx in 0 until zw) {
                val p     = (rowBase + zx + dx) * 3
                val lStar = (lab[p].toInt() and 0xFF) * (100.0 / 255.0)
                val ac    = (lab[p + 1].toInt() and 0xFF) - 128.0
                val bc    = (lab[p + 2].toInt() and 0xFF) - 128.0
                val c     = sqrt(ac * ac + bc * bc)
                val cc    = chromaClass(c)
                val hDeg  = if (cc > 0) {
                    var h = Math.toDegrees(atan2(bc, ac)); if (h < 0) h += 360.0; h
                } else 0.0
                hist[segId(lStarClass(lStar), cc, if (cc == 0) 0 else hueClass(hDeg))]++
            }
        }
        return hist.indices.maxByOrNull { hist[it] } ?: 0
    }

    // ΔE для каждой зоны grid×grid через 803-сегментные LCH-дескрипторы.
    // refLab / cmpLab — Mat CV_8UC3 канонического разрешения.
    private fun zoneDE(
        refLab: Mat, cmpLab: Mat,
        imgW: Int, imgH: Int, grid: Int, wL: Double
    ): DoubleArray {
        val zw = imgW / grid; val zh = imgH / grid
        val refArr = ByteArray(imgW * imgH * 3); refLab.get(0, 0, refArr)
        val cmpArr = ByteArray(imgW * imgH * 3); cmpLab.get(0, 0, cmpArr)
        return DoubleArray(grid * grid) { i ->
            val row = i / grid; val col = i % grid
            segDE(
                dominantSeg(refArr, imgW, col * zw, row * zh, zw, zh),
                dominantSeg(cmpArr, imgW, col * zw, row * zh, zw, zh),
                wL
            )
        }
    }


    // Визуализация diff: cellPx×cellPx пикселей на зону, PNG с прозрачностью
    // Каналы Mat: (R, G, B, A) — PNG-декодер Flutter читает в этом порядке как RGBA
    // Строит PNG-карту ΔE. Размер выходного изображения = nw × nh (как canonical),
    // чтобы diff точно накладывался на canonical ref.
    // Пороги: ΔE<3 зелёный, 3-6 жёлтый, >6 красный.
    // Scalar порядок: BGRA (OpenCV) — imencode конвертирует в RGBA для PNG.
    private fun buildZoneDiff(de: DoubleArray, grid: Int, nw: Int, nh: Int): ByteArray {
        val cw = nw / grid; val ch = nh / grid   // ширина и высота одной ячейки
        val out = Mat(nh, nw, CvType.CV_8UC4, Scalar(0.0, 0.0, 0.0, 0.0))
        for (i in de.indices) {
            val row = i / grid; val col = i % grid
            val d = de[i]
            val r: Int; val g: Int; val b: Int; val a: Int
            when {
                d < 3.0  -> { r=30;  g=200; b=30;  a=(d/3.0*100).toInt().coerceIn(20,100) }
                d < 6.0  -> {
                    val t = (d - 3.0) / 3.0
                    r=(30  + (225*t)).toInt()
                    g=(200 - (50 *t)).toInt()
                    b=30
                    a=(100 + (120*t)).toInt()
                }
                else     -> { r=220; g=20;  b=20;  a=220 }
            }
            // Scalar(B, G, R, A) — OpenCV channel order
            out.submat(Rect(col*cw, row*ch, cw, ch))
               .setTo(Scalar(b.toDouble(), g.toDouble(), r.toDouble(), a.toDouble()))
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
