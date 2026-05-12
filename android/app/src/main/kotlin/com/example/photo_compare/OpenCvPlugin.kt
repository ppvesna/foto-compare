package com.example.photo_compare

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.opencv.android.Utils
import org.opencv.calib3d.Calib3d
import org.opencv.core.*
import org.opencv.features2d.BFMatcher
import org.opencv.features2d.ORB
import org.opencv.imgproc.Imgproc
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

        val refGray = Mat(); val srcGray = Mat()
        Imgproc.cvtColor(ref, refGray, Imgproc.COLOR_BGR2GRAY)
        Imgproc.cvtColor(src, srcGray, Imgproc.COLOR_BGR2GRAY)

        val orb = ORB.create(2000)
        val kp1 = MatOfKeyPoint(); val kp2 = MatOfKeyPoint()
        val d1 = Mat(); val d2 = Mat()
        orb.detectAndCompute(refGray, Mat(), kp1, d1)
        orb.detectAndCompute(srcGray, Mat(), kp2, d2)

        if (d1.empty() || d2.empty()) return srcBytes

        val matcher = BFMatcher.create(org.opencv.core.CvType.CV_8U, true)
        val matches = MatOfDMatch()
        matcher.match(d1, d2, matches)

        val allMatches = matches.toArray().sortedBy { it.distance }
        val good = allMatches.take((allMatches.size * 0.2).toInt().coerceAtLeast(8))
        if (good.size < 4) return srcBytes

        val kp1List = kp1.toArray(); val kp2List = kp2.toArray()
        val pts1 = MatOfPoint2f(*good.map { kp1List[it.queryIdx].pt }.toTypedArray())
        val pts2 = MatOfPoint2f(*good.map { kp2List[it.trainIdx].pt }.toTypedArray())

        val H = Calib3d.findHomography(pts2, pts1, Calib3d.RANSAC, 5.0)
        if (H.empty()) return srcBytes

        val aligned = Mat()
        Imgproc.warpPerspective(src, aligned, H, ref.size())
        return matToBytes(aligned)
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
